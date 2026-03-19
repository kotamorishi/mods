import SwiftUI
import UniformTypeIdentifiers

@main
struct modsApp: App {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.openFileAction) private var openFileAction
    @FocusedValue(\.findAction) private var findAction
    @FocusedValue(\.printAction) private var printAction
    @FocusedValue(\.exportPDFAction) private var exportPDFAction
    @FocusedValue(\.tocAction) private var tocAction

    var body: some Scene {
        // Welcome window (no file)
        WindowGroup(id: "welcome") {
            WelcomeView()
        }
        // File viewer windows
        WindowGroup(for: URL.self) { $url in
            if let url {
                FileView(initialURL: url)
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    if let openFileAction {
                        openFileAction()
                    } else {
                        openFileFallback()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    findAction?()
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Table of Contents") {
                    tocAction?()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .printItem) {
                Button("Print...") {
                    printAction?()
                }
                .keyboardShortcut("p", modifiers: .command)
                Divider()
                Button("Export as PDF...") {
                    exportPDFAction?()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    private func openFileFallback() {
        for url in FilePickerHelper.runOpenPanel() {
            openWindow(value: url)
        }
    }
}

/// Welcome window: shown on launch, allows opening a file.
struct WelcomeView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Text("Drop a markdown file or use File > Open")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 400, minHeight: 300)
            .focusedSceneValue(\.openFileAction, openFile)
            .onOpenURL { url in
                openWindow(value: Self.resolveURL(url))
                dismissWindow(id: "welcome")
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, URLValidator.isSafe(url) {
                        DispatchQueue.main.async {
                            openWindow(value: url)
                            dismissWindow(id: "welcome")
                        }
                    }
                }
                return true
            }
    }

    private func openFile() {
        let urls = FilePickerHelper.runOpenPanel()
        for url in urls {
            openWindow(value: url)
        }
        if !urls.isEmpty {
            dismissWindow(id: "welcome")
        }
    }

    /// Convert mods:// URLs to file URLs with security validation.
    private static func resolveURL(_ url: URL) -> URL {
        if url.scheme == "mods" {
            return URLValidator.resolve(modsURL: url) ?? url
        }
        return url
    }
}

/// Validates and resolves file URLs for security.
enum URLValidator {
    /// Strict: only markdown extensions (for mods:// URL scheme — external input)
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    /// Permissive: also allow plain text (for drag & drop, File > Open — user-initiated)
    private static let viewableExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]

    /// Resolve a mods:// URL to a safe file URL (strict: markdown only).
    static func resolve(modsURL url: URL) -> URL? {
        let fileURL = URL(fileURLWithPath: url.path).standardizedFileURL
        guard markdownExtensions.contains(fileURL.pathExtension.lowercased()) else {
            return nil
        }
        return fileURL
    }

    /// Validate a file URL for safe opening (permissive: user-initiated).
    static func isSafe(_ url: URL) -> Bool {
        if url.scheme == "mods" {
            return resolve(modsURL: url) != nil
        }
        if url.isFileURL {
            return viewableExtensions.contains(url.pathExtension.lowercased())
        }
        return true
    }
}

/// File viewer window: shows rendered markdown for a single file.
struct FileView: View {
    let initialURL: URL
    @Environment(\.openWindow) private var openWindow
    @State private var fileURL: URL?
    @State private var markdown: String = ""
    @State private var zoomLevel: Double = 1.0
    @State private var fileWatcher: FileWatcher?
    @State private var findTrigger: Int = 0
    @State private var printTrigger: Int = 0
    @State private var exportPDFTrigger: Int = 0
    @State private var tocScrollTarget: String = ""
    @State private var showTOC: Bool = false

    private var headings: [(level: Int, text: String)] {
        markdown.components(separatedBy: "\n")
            .compactMap { line -> (Int, String)? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") else { return nil }
                var level = 0
                for ch in trimmed { if ch == "#" { level += 1 } else { break } }
                guard level >= 1 && level <= 6 else { return nil }
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return nil }
                return (level, text)
            }
    }

    private var wordCount: Int {
        markdown.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var readingTime: String {
        let minutes = max(1, wordCount / 200)
        return "\(minutes) min read"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MarkdownWebView(markdown: markdown, zoomLevel: zoomLevel, findTrigger: findTrigger, printTrigger: printTrigger, exportPDFTrigger: exportPDFTrigger, tocScrollTarget: tocScrollTarget)

                if showTOC && !headings.isEmpty {
                    Divider()
                    TOCSidebar(headings: headings) { heading in
                        tocScrollTarget = heading
                    }
                }
            }
            if !markdown.isEmpty {
                HStack {
                    Text("\(wordCount) words")
                    Text("·")
                    Text(readingTime)
                    Spacer()
                    if let fileURL {
                        Text(fileURL.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(fileURL?.lastPathComponent ?? "mods")
            .toolbar {
                ToolbarItem {
                    Button {
                        showTOC.toggle()
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .help("Toggle Outline")
                }
                ToolbarItemGroup {
                    Button {
                        zoomLevel = max(0.25, zoomLevel - 0.1)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .keyboardShortcut("-", modifiers: .command)

                    Button {
                        zoomLevel = 1.0
                    } label: {
                        Text("\(Int(zoomLevel * 100))%")
                            .monospacedDigit()
                            .frame(minWidth: 40)
                    }
                    .keyboardShortcut("0", modifiers: .command)

                    Button {
                        zoomLevel = min(5.0, zoomLevel + 0.1)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .keyboardShortcut("+", modifiers: .command)
                }
            }
            .focusedSceneValue(\.openFileAction, openFile)
            .focusedSceneValue(\.findAction, performFind)
            .focusedSceneValue(\.printAction, performPrint)
            .focusedSceneValue(\.exportPDFAction, performExportPDF)
            .focusedSceneValue(\.tocAction, toggleTOC)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, URLValidator.isSafe(url) {
                        DispatchQueue.main.async {
                            openWindow(value: url)
                        }
                    }
                }
                return true
            }
            .onOpenURL { url in
                let resolved = url.scheme == "mods" ? (URLValidator.resolve(modsURL: url) ?? url) : url
                openWindow(value: resolved)
            }
            .onDisappear {
                fileWatcher?.stop()
            }
            .onAppear {
                loadURL(initialURL)
            }
    }

    private func performFind() { findTrigger += 1 }
    private func performPrint() { printTrigger += 1 }
    private func performExportPDF() { exportPDFTrigger += 1 }
    private func toggleTOC() { showTOC.toggle() }

    private func openFile() {
        for url in FilePickerHelper.runOpenPanel() {
            openWindow(value: url)
        }
    }

    private static let maxFileSize: UInt64 = 10 * 1024 * 1024

    private func loadURL(_ url: URL) {
        self.fileURL = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size > Self.maxFileSize {
            let sizeMB = String(format: "%.1f", Double(size) / 1_048_576)
            self.markdown = "# File too large\n\nThis file is \(sizeMB) MB. Maximum supported size is 10 MB."
            return
        }

        self.markdown = HTMLBuilder.readFileWithFallback(url: url)
        startWatching(url)
    }

    private func startWatching(_ url: URL) {
        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url) {
            let newContent = HTMLBuilder.readFileWithFallback(url: url)
            if newContent != self.markdown {
                self.markdown = newContent
            }
        }
        fileWatcher?.start()
    }
}

struct OpenFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FindActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct PrintActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ExportPDFActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct TOCActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openFileAction: (() -> Void)? {
        get { self[OpenFileActionKey.self] }
        set { self[OpenFileActionKey.self] = newValue }
    }
    var findAction: (() -> Void)? {
        get { self[FindActionKey.self] }
        set { self[FindActionKey.self] = newValue }
    }
    var printAction: (() -> Void)? {
        get { self[PrintActionKey.self] }
        set { self[PrintActionKey.self] = newValue }
    }
    var exportPDFAction: (() -> Void)? {
        get { self[ExportPDFActionKey.self] }
        set { self[ExportPDFActionKey.self] = newValue }
    }
    var tocAction: (() -> Void)? {
        get { self[TOCActionKey.self] }
        set { self[TOCActionKey.self] = newValue }
    }
}

/// VS Code-style outline sidebar showing heading hierarchy.
struct TOCSidebar: View {
    let headings: [(level: Int, text: String)]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OUTLINE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                        Button {
                            onSelect(heading.text)
                        } label: {
                            Text(heading.text)
                                .font(.system(size: heading.level <= 2 ? 12 : 11,
                                              weight: heading.level <= 1 ? .semibold : .regular))
                                .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, CGFloat((heading.level - 1) * 10))
                                .padding(.vertical, 3)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 220)
        .background(.background)
    }
}

/// Shared file picker for markdown files.
enum FilePickerHelper {
    @MainActor static func runOpenPanel() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            return panel.urls
        }
        return []
    }
}
