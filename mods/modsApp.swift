import SwiftUI
import UniformTypeIdentifiers

@main
struct modsApp: App {
    @FocusedValue(\.openFileAction) private var openFileAction
    @FocusedValue(\.findAction) private var findAction
    @FocusedValue(\.printAction) private var printAction

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
                    openFileAction?()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    findAction?()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print...") {
                    printAction?()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
    }
}

/// Welcome window: shown on launch, allows opening a file.
struct WelcomeView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Drop a markdown file or use File > Open")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 400, minHeight: 300)
            .focusedSceneValue(\.openFileAction, openFile)
            .onOpenURL { url in
                openWindow(value: url)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        DispatchQueue.main.async {
                            openWindow(value: url)
                        }
                    }
                }
                return true
            }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                openWindow(value: url)
            }
        }
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

    var body: some View {
        MarkdownWebView(markdown: markdown, zoomLevel: zoomLevel, findTrigger: findTrigger, printTrigger: printTrigger)
            .frame(minWidth: 400, minHeight: 300)
            .navigationTitle(fileURL?.lastPathComponent ?? "mods")
            .toolbar {
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
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        DispatchQueue.main.async {
                            openWindow(value: url)
                        }
                    }
                }
                return true
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

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                openWindow(value: url)
            }
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
}
