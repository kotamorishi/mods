import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Handles file open events from Finder (double-click, "Open With").
class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var pendingURLs: [URL] = []
    private var didFinishLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSWindow.installTabbingSwizzle()
        didFinishLaunch = true
        // Open any URLs that arrived before launch finished
        let urls = Self.pendingURLs
        Self.pendingURLs = []
        for url in urls {
            NotificationCenter.default.post(name: .openFileFromFinder, object: url)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if didFinishLaunch {
            for url in urls {
                NotificationCenter.default.post(name: .openFileFromFinder, object: url)
            }
        } else {
            Self.pendingURLs.append(contentsOf: urls)
        }
    }
}

extension NSWindow {
    static func installTabbingSwizzle() {
        let original = #selector(NSWindow.makeKeyAndOrderFront(_:))
        let swizzled = #selector(NSWindow.mods_makeKeyAndOrderFront(_:))
        guard let m1 = class_getInstanceMethod(NSWindow.self, original),
              let m2 = class_getInstanceMethod(NSWindow.self, swizzled) else { return }
        method_exchangeImplementations(m1, m2)
    }

    @objc func mods_makeKeyAndOrderFront(_ sender: Any?) {
        if !(self is NSPanel) && styleMask.contains(.titled) && styleMask.contains(.closable) {
            tabbingMode = .preferred
            tabbingIdentifier = "com.mods.viewer"
        }
        mods_makeKeyAndOrderFront(sender)
    }
}

extension Notification.Name {
    static let openFileFromFinder = Notification.Name("openFileFromFinder")
}

@main
struct modsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusedValue(\.openFileAction) private var openFileAction
    @FocusedValue(\.findAction) private var findAction
    @FocusedValue(\.printAction) private var printAction
    @FocusedValue(\.exportPDFAction) private var exportPDFAction
    @FocusedValue(\.tocAction) private var tocAction
    @FocusedValue(\.clearHighlightsAction) private var clearHighlightsAction
    @FocusedValue(\.zoomInAction) private var zoomInAction
    @FocusedValue(\.zoomOutAction) private var zoomOutAction
    @FocusedValue(\.zoomResetAction) private var zoomResetAction
    @FocusedValue(\.findNextAction) private var findNextAction
    @FocusedValue(\.findPrevAction) private var findPrevAction
    @FocusedValue(\.copyRichTextAction) private var copyRichTextAction
    @FocusedValue(\.compareAction) private var compareAction

    var body: some Scene {
        // Welcome window (no file)
        WindowGroup(id: "welcome") {
            WelcomeView()
                .onReceive(NotificationCenter.default.publisher(for: .openFileFromFinder)) { notification in
                    if let url = notification.object as? URL {
                        openWindow(value: url)
                        DispatchQueue.main.async { WelcomeView.closeWelcomeWindow() }
                    }
                }
        }
        // File viewer windows
        WindowGroup(for: URL.self) { $url in
            if let url {
                FileView(initialURL: url)
                    .onReceive(NotificationCenter.default.publisher(for: .openFileFromFinder)) { notification in
                        if let fileURL = notification.object as? URL {
                            openWindow(value: fileURL)
                        }
                    }
            }
        }
        // Diff comparison windows
        WindowGroup(for: DiffData.self) { $data in
            if let data {
                DiffView(data: data)
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
                Button("Find Next") {
                    findNextAction?()
                }
                .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") {
                    findPrevAction?()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Clear All Highlights") {
                    clearHighlightsAction?()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Toggle Sidebar") {
                    tocAction?()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    zoomInAction?()
                }
                .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") {
                    zoomOutAction?()
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") {
                    zoomResetAction?()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy as Rich Text") {
                    copyRichTextAction?()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .printItem) {
                Button("Compare with...") {
                    compareAction?()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
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
    @State private var highlightKeywords: [String] = HighlightKeywords.keywords()
    @State private var newKeyword: String = ""
    @State private var trustedDomains: [String] = Array(TrustedImageDomains.trustedDomains()).sorted()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("Mods")
                .font(.title)
                .fontWeight(.semibold)
            Text("Markdown Viewer for macOS")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider().frame(width: 200)
            VStack(alignment: .leading, spacing: 8) {
                Label("Drop a file here to open", systemImage: "arrow.down.doc")
                Label("File > Open or Cmd+O", systemImage: "folder")
                Label("Double-click .md files in Finder", systemImage: "cursorarrow.click.2")
                Label("Press Space in Finder for QuickLook", systemImage: "eye")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)

            // Keyword highlight editor
            VStack(spacing: 8) {
                Divider().frame(width: 200)
                Label("Highlight Keywords", systemImage: "highlighter")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Shared with QuickLook")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    TextField("Add keyword...", text: $newKeyword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit { addKeyword() }
                    Button(action: addKeyword) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !highlightKeywords.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(highlightKeywords, id: \.self) { keyword in
                            HStack(spacing: 4) {
                                Text(keyword)
                                    .lineLimit(1)
                                Button {
                                    removeKeyword(keyword)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                    .frame(maxWidth: 300)
                }
            }

            // Trusted domains editor
            if !trustedDomains.isEmpty {
                VStack(spacing: 8) {
                    Divider().frame(width: 200)
                    Label("Auto-Load Images From", systemImage: "photo.badge.checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(trustedDomains, id: \.self) { domain in
                            HStack(spacing: 4) {
                                Text(domain)
                                    .lineLimit(1)
                                Button {
                                    removeTrustedDomain(domain)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                    .frame(maxWidth: 300)
                }
            }

            Spacer()
            HStack(spacing: 4) {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                Text("·")
                Text("GFM · Syntax Highlighting · KaTeX · Mermaid")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 400, minHeight: 420)
        .focusedSceneValue(\.openFileAction, openFile)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                highlightKeywords = HighlightKeywords.keywords()
                trustedDomains = Array(TrustedImageDomains.trustedDomains()).sorted()
            }
            .onAppear {
                // Tag the welcome window so we can find it later
                DispatchQueue.main.async {
                    NSApp.keyWindow?.identifier = NSUserInterfaceItemIdentifier("welcome")
                }
                let pending = AppDelegate.pendingURLs
                AppDelegate.pendingURLs = []
                if !pending.isEmpty {
                    for url in pending {
                        openWindow(value: url)
                    }
                    DispatchQueue.main.async {
                        Self.closeWelcomeWindow()
                    }
                }
            }
            .onOpenURL { url in
                openWindow(value: Self.resolveURL(url))
                DispatchQueue.main.async { Self.closeWelcomeWindow() }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, URLValidator.isSafe(url) {
                        DispatchQueue.main.async {
                            openWindow(value: url)
                            DispatchQueue.main.async { Self.closeWelcomeWindow() }
                        }
                    }
                }
                return true
            }
    }

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !highlightKeywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        highlightKeywords.append(trimmed)
        HighlightKeywords.save(highlightKeywords)
        newKeyword = ""
    }

    private func removeKeyword(_ keyword: String) {
        highlightKeywords.removeAll { $0 == keyword }
        HighlightKeywords.save(highlightKeywords)
    }

    private func removeTrustedDomain(_ domain: String) {
        TrustedImageDomains.removeDomain(domain)
        trustedDomains = Array(TrustedImageDomains.trustedDomains()).sorted()
    }

    private func openFile() {
        let urls = FilePickerHelper.runOpenPanel()
        for url in urls {
            openWindow(value: url)
        }
        if !urls.isEmpty {
            DispatchQueue.main.async { Self.closeWelcomeWindow() }
        }
    }

    static func closeWelcomeWindow() {
        for window in NSApp.windows where window.identifier?.rawValue == "welcome" {
            window.close()
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
        let fileURL = URL(fileURLWithPath: url.path).standardizedFileURL.resolvingSymlinksInPath()
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
        return false
    }
}

/// Data for side-by-side diff comparison window.
struct DiffData: Codable, Hashable {
    let leftURL: URL
    let rightURL: URL
}

/// Side-by-side comparison view for two markdown files.
struct DiffView: View {
    let data: DiffData
    @State private var leftMarkdown: String = ""
    @State private var rightMarkdown: String = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(data.leftURL.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
                Divider()
                DiffWebView(html: renderHTML(leftMarkdown))
            }
            Divider()
            VStack(spacing: 0) {
                Text(data.rightURL.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
                Divider()
                DiffWebView(html: renderHTML(rightMarkdown))
            }
        }
        .frame(minWidth: 800, minHeight: 400)
        .navigationTitle("\(data.leftURL.lastPathComponent) ↔ \(data.rightURL.lastPathComponent)")
        .onAppear {
            leftMarkdown = HTMLBuilder.readFileWithFallback(url: data.leftURL)
            rightMarkdown = HTMLBuilder.readFileWithFallback(url: data.rightURL)
        }
    }

    private func renderHTML(_ markdown: String) -> String {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
        return HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
    }
}

/// Simple read-only WKWebView for diff display.
struct DiffWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: HTMLBuilder.webViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        if !html.isEmpty {
            webView.loadHTMLString(html, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if !html.isEmpty {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

/// File viewer window: shows rendered markdown for a single file.
struct FileView: View {
    let initialURL: URL
    @Environment(\.openWindow) private var openWindow
    @State private var fileURL: URL?
    @State private var markdown: String = ""
    @AppStorage("zoomLevel") private var zoomLevel: Double = 1.0
    @State private var fileWatcher: FileWatcher?
    @State private var securityScopedDir: URL?  // keeps directory access alive for file watcher
    @State private var hasDirectoryAccess: Bool = false
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var search = SearchState()
    @State private var activeSearchTerms: [(term: String, slot: Int, count: Int, current: Int)] = []
    @State private var searchStack: [[String]] = []
    @State private var suggestionWords: [String] = []
    @State private var printTrigger: Int = 0
    @State private var exportPDFTrigger: Int = 0
    @State private var tocScrollTarget: String = ""
    @AppStorage("showSidebar") private var showSidebar: Bool = false
    @AppStorage("showFiles") private var showFiles: Bool = true
    @AppStorage("showTOC") private var showTOC: Bool = true
    @AppStorage("tocWidth") private var tocWidth: Double = 220
    @AppStorage("filesHeight") private var filesHeight: Double = 0
    @State private var headings: [(level: Int, text: String, id: String)] = []
    @State private var pages: [String] = []
    @State private var currentPage: Int = 0
    @State private var currentPageHTML: String = ""
    @State private var siblingFiles: [URL] = []
    @State private var scrollToTopTrigger: Int = 0
    @State private var copyRichTextTrigger: Int = 0
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var showDiffHighlights: Bool = false
    @State private var diffHunks: [MarkdownRenderer.DiffHunk] = []
    @State private var applyDiffTrigger: Int = 0
    @State private var clearDiffTrigger: Int = 0
    @State private var scrollToDiffTrigger: Int = 0

    private static func parseHeadings(_ markdown: String) -> [(level: Int, text: String, id: String)] {
        var counts: [String: Int] = [:]
        return markdown.components(separatedBy: "\n")
            .compactMap { line -> (Int, String, String)? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") else { return nil }
                var level = 0
                for ch in trimmed { if ch == "#" { level += 1 } else { break } }
                guard level >= 1 && level <= 6 else { return nil }
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return nil }
                var slug = text.lowercased()
                    .replacingOccurrences(of: "[^a-z0-9\\s-]", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                if slug.isEmpty { slug = "heading" }
                let count = counts[slug, default: 0]
                counts[slug] = count + 1
                let id = count == 0 ? slug : "\(slug)-\(count)"
                return (level, text, id)
            }
    }

    private var currentPageHeadings: [(level: Int, text: String, id: String)] {
        guard !pages.isEmpty, currentPage < pages.count else { return headings }
        return Self.parseHeadings(pages[currentPage])
    }

    private var wordCount: Int {
        markdown.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        mainContent
            .onOpenURL(perform: handleOpenURL)
            .onDisappear {
                fileWatcher?.stop()
                securityScopedDir?.stopAccessingSecurityScopedResource()
            }
            .onAppear { loadURL(initialURL) }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, URLValidator.isSafe(url) {
                        DispatchQueue.main.async {
                            self.openWindow(value: url)
                        }
                    }
                }
                return true
            }
    }

    private var mainContent: some View {
        mainLayout
            .focusedSceneValue(\.openFileAction, openFile)
            .focusedSceneValue(\.findAction, performFind)
            .focusedSceneValue(\.printAction, performPrint)
            .focusedSceneValue(\.exportPDFAction, performExportPDF)
            .focusedSceneValue(\.tocAction, toggleSidebar)
            .focusedSceneValue(\.clearHighlightsAction, clearHighlights)
            .focusedSceneValue(\.zoomInAction, performZoomIn)
            .focusedSceneValue(\.zoomOutAction, performZoomOut)
            .focusedSceneValue(\.zoomResetAction, performZoomReset)
            .focusedSceneValue(\.findNextAction, performFindNext)
            .focusedSceneValue(\.findPrevAction, performFindPrev)
            .focusedSceneValue(\.copyRichTextAction, performCopyRichText)
            .focusedSceneValue(\.compareAction, performCompare)
    }

    private var mainLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                contentArea
                bottomBar
            }
            if showToast {
                toastView
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(fileURL?.lastPathComponent ?? "mods")
        .toolbar { toolbarContent }
        .searchable(text: $searchText, isPresented: $isSearching, placement: .toolbar, prompt: "Search...")
        .searchSuggestions {
            ForEach(filteredSuggestions, id: \.self) { word in
                Text(word).searchCompletion(word)
            }
        }
        .onSubmit(of: .search, submitSearch)
        .onChange(of: searchText) { onSearchTextChange() }
        .onChange(of: isSearching) { onSearchDismiss() }
        .onChange(of: markdown) {
            headings = Self.parseHeadings(markdown)
            paginateMarkdown()
            updateSuggestions()
        }
    }

    /// Row height (22) + intercell spacing (1) per file row, plus folder path line (~18) + padding.
    private static let fileRowHeight: CGFloat = 23
    private static let filesHeaderExtra: CGFloat = 22
    private static let maxVisibleFiles: Int = 7

    private var filesContentHeight: CGFloat {
        let rowsHeight = CGFloat(siblingFiles.count) * Self.fileRowHeight + Self.filesHeaderExtra
        let maxHeight = CGFloat(Self.maxVisibleFiles) * Self.fileRowHeight + Self.filesHeaderExtra
        return min(rowsHeight, maxHeight)
    }

    private var effectiveFilesHeight: CGFloat {
        if filesHeight > 0 {
            // User-set height, but still clamp to content height when fewer files
            let maxHeight = CGFloat(Self.maxVisibleFiles) * Self.fileRowHeight + Self.filesHeaderExtra
            return min(filesHeight, maxHeight)
        }
        return filesContentHeight
    }

    private var contentArea: some View {
        HStack(spacing: 0) {
            if showSidebar {
                VStack(spacing: 0) {
                    if fileURL != nil {
                        SidebarSectionHeader(title: "FILES", isExpanded: $showFiles)
                        if showFiles {
                            VStack(spacing: 0) {
                                if let fileURL {
                                    Text(fileURL.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.bottom, 4)
                                        .onTapGesture {
                                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                                        }
                                        .cursor(.pointingHand)
                                }
                                FilesSidebar(files: siblingFiles, currentFile: fileURL) { url in
                                    openSiblingFile(url)
                                }
                                if !hasDirectoryAccess {
                                    Button { grantDirectoryAccess() } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder.badge.plus")
                                            Text("Grant folder access for live reload")
                                        }
                                        .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                }
                            }
                            .frame(height: effectiveFilesHeight)
                            VerticalResizeHandle(height: $filesHeight, minHeight: Self.fileRowHeight + Self.filesHeaderExtra, maxHeight: CGFloat(Self.maxVisibleFiles) * Self.fileRowHeight + Self.filesHeaderExtra)
                        }
                        Divider()
                    }
                    if !headings.isEmpty {
                        SidebarSectionHeader(title: "OUTLINE", isExpanded: $showTOC)
                        if showTOC {
                            TOCSidebar(headings: headings, zoomLevel: zoomLevel, width: tocWidth) { heading in
                                navigateToHeading(heading)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: max(120, min(500, tocWidth)))
                ResizableHandle(width: $tocWidth)
            }
            markdownWebView
        }
    }

    @ViewBuilder
    private var toastView: some View {
        HStack(spacing: 8) {
            let icon = showDiffHighlights ? "plus.forwardslash.minus" : "checkmark.circle.fill"
            let color: Color = showDiffHighlights ? .orange : .green
            Image(systemName: icon).foregroundStyle(color)
            if showDiffHighlights {
                Button {
                    scrollToDiffTrigger += 1
                } label: {
                    HStack(spacing: 4) {
                        Text(toastMessage)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                }
                .buttonStyle(.plain)
                Button("Hide diff") {
                    showDiffHighlights = false
                    clearDiffTrigger += 1
                    withAnimation(.easeInOut(duration: 0.3)) { showToast = false }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .fontWeight(.semibold)
            } else {
                Text(toastMessage)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 32)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !markdown.isEmpty || !activeSearchTerms.isEmpty || !searchStack.isEmpty {
            VStack(spacing: 0) {
                if !activeSearchTerms.isEmpty || !searchStack.isEmpty {
                    searchTermsBar
                }
                if !markdown.isEmpty {
                    statusBar
                }
            }
            .background(.bar)
        }
    }

    private var searchTermsBar: some View {
        SearchTermsBar(terms: activeSearchTerms, stack: searchStack, caseSensitive: $search.caseSensitive, wholeWord: $search.wholeWord, onTap: { term in
            search.lastNavigatedTerm = term
            search.scrollToNextTerm = term
            search.scrollToNextTrigger += 1
        }, onRemove: { term in
            search.removeTerm = term
            search.removeTrigger += 1
        }, onPush: {
            search.pushTrigger += 1
        }, onPop: {
            search.popTrigger += 1
        }, onRestore: { index in
            search.restoreIndex = index
            search.restoreTrigger += 1
        }, onClearAll: {
            search.clearTrigger += 1
        })
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text("\(wordCount) words")
            if pages.count > 1 {
                Divider().frame(height: 12)
                Button { goToPage(currentPage - 1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(currentPage <= 0)
                Text("\(currentPage + 1)/\(pages.count)")
                    .monospacedDigit()
                Button { goToPage(currentPage + 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= pages.count - 1)
            }
            Spacer()
            if let fileURL {
                Text(fileURL.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Divider().frame(height: 12)
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            CompactSlider(value: $zoomLevel, in: 0.25...5.0, step: 0.05)
                .frame(width: 100)
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("\(Int(zoomLevel * 100))%")
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .trailing)
                .onTapGesture { zoomLevel = 1.0 }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var markdownWebView: some View {
        MarkdownWebView(markdown: currentPageHTML.isEmpty ? markdown : currentPageHTML, zoomLevel: $zoomLevel, search: search, activeSearchTerms: $activeSearchTerms, searchStack: $searchStack, printTrigger: printTrigger, exportPDFTrigger: exportPDFTrigger, copyRichTextTrigger: copyRichTextTrigger, tocScrollTarget: tocScrollTarget, scrollToTopTrigger: scrollToTopTrigger, diffHunks: diffHunks, applyDiffTrigger: applyDiffTrigger, clearDiffTrigger: clearDiffTrigger, scrollToDiffTrigger: scrollToDiffTrigger)
    }

    private var filteredSuggestions: [String] {
        guard searchText.count >= 2 else { return [] }
        return suggestionWords
            .filter { $0.localizedCaseInsensitiveContains(searchText) }
            .prefix(10)
            .map { $0 }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .help("Toggle Sidebar")
        }
    }

    private func submitSearch() {
        guard searchText.count >= 2 && searchText.count <= 256 else { return }
        search.text = searchText
        search.addTrigger += 1
        searchText = ""
    }

    private func performFind() { isSearching.toggle() }
    private func performPrint() { printTrigger += 1 }
    private func performExportPDF() { exportPDFTrigger += 1 }
    private func toggleSidebar() { showSidebar.toggle() }
    private func clearHighlights() { search.clearTrigger += 1 }
    private func performZoomIn() { zoomLevel = min(5.0, zoomLevel + 0.1) }
    private func performZoomOut() { zoomLevel = max(0.25, zoomLevel - 0.1) }
    private func performZoomReset() { zoomLevel = 1.0 }
    private func performCopyRichText() { copyRichTextTrigger += 1 }
    private func grantDirectoryAccess() {
        guard let fileURL else { return }
        let dir = fileURL.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.directoryURL = dir
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Grant access to this folder for live file reload and sidebar"
        panel.prompt = "Allow"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Save bookmark
        DirectoryBookmarks.saveBookmark(forDirectory: url)
        // Start accessing
        securityScopedDir?.stopAccessingSecurityScopedResource()
        if url.startAccessingSecurityScopedResource() {
            securityScopedDir = url
        }
        hasDirectoryAccess = true
        updateSiblingFiles()
    }
    private func performCompare() {
        guard let fileURL else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select a file to compare with"
        guard panel.runModal() == .OK, let rightURL = panel.url else { return }
        openWindow(value: DiffData(leftURL: fileURL, rightURL: rightURL))
    }
    private func showToast(_ message: String, autoDismiss: Bool = true) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) { showToast = true }
        if autoDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) { self.showToast = false }
            }
        }
    }
    private func showDiffToast() {
        let addCount = diffHunks.reduce(0) { $0 + $1.addedLines.count }
        let delCount = diffHunks.reduce(0) { $0 + $1.removedLines.count }
        let parts = [addCount > 0 ? "+\(addCount)" : nil, delCount > 0 ? "-\(delCount)" : nil].compactMap { $0 }
        let summary = parts.isEmpty ? "File updated" : "File updated (\(parts.joined(separator: " ")))"
        showToast(summary, autoDismiss: false)
    }
    private func performFindNext() {
        let term = search.lastNavigatedTerm.isEmpty ? activeSearchTerms.last?.term ?? "" : search.lastNavigatedTerm
        guard !term.isEmpty else { return }
        search.scrollToNextTerm = term
        search.scrollToNextTrigger += 1
    }
    private func onSearchTextChange() {
        search.previewText = searchText
    }

    private func onSearchDismiss() {
        if !isSearching {
            searchText = ""
            search.previewText = ""
        }
    }

    private func updateSuggestions() {
        let text = markdown
        Task.detached(priority: .utility) {
            let words = WordExtractor.extractWords(from: text)
            await MainActor.run { suggestionWords = words }
        }
    }

    private func performFindPrev() {
        let term = search.lastNavigatedTerm.isEmpty ? activeSearchTerms.last?.term ?? "" : search.lastNavigatedTerm
        guard !term.isEmpty else { return }
        search.scrollToPrevTerm = term
        search.scrollToPrevTrigger += 1
    }

    private func handleOpenURL(_ url: URL) {
        if url.scheme == "mods" {
            guard let resolved = URLValidator.resolve(modsURL: url) else { return }
            openWindow(value: resolved)
        } else {
            openWindow(value: url)
        }
    }

    private func openFile() {
        for url in FilePickerHelper.runOpenPanel() {
            openWindow(value: url)
        }
    }

    private func openSiblingFile(_ url: URL) {
        guard url != fileURL else { return }
        // Check if the file is already open in another window/tab and activate it
        for window in NSApplication.shared.windows where window.title == url.lastPathComponent {
            window.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(value: url)
    }

    private static let maxFileSize: UInt64 = 10 * 1024 * 1024

    private func loadURL(_ url: URL) {
        // Scroll to top when switching to a different file
        if fileURL != nil && fileURL != url {
            scrollToTopTrigger += 1
        }
        self.fileURL = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        // Save directory bookmark for re-reading after atomic saves
        DirectoryBookmarks.saveBookmark(for: url)
        // Keep directory access alive for file watcher re-reads
        securityScopedDir?.stopAccessingSecurityScopedResource()
        let dir = url.deletingLastPathComponent()
        if dir.startAccessingSecurityScopedResource() {
            securityScopedDir = dir
        } else {
            securityScopedDir = DirectoryBookmarks.startAccessing(for: url)
        }
        hasDirectoryAccess = (securityScopedDir != nil)

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size > Self.maxFileSize {
            let sizeMB = String(format: "%.1f", Double(size) / 1_048_576)
            self.markdown = "# File too large\n\nThis file is \(sizeMB) MB. Maximum supported size is 10 MB."
            return
        }

        self.markdown = HTMLBuilder.readFileWithFallback(url: url)
        self.headings = Self.parseHeadings(markdown)
        paginateMarkdown()
        updateSiblingFiles()
        startWatching(url)
    }

    /// Split markdown into pages by top-level headings for large files.
    private static let markdownHeadingRegex = try! NSRegularExpression(pattern: "(?m)^#{1,2}\\s+")
    private static let paginationThreshold = 200_000

    private func paginateMarkdown() {
        guard markdown.count > Self.paginationThreshold else {
            pages = []
            currentPage = 0
            currentPageHTML = ""
            return
        }

        let nsMarkdown = markdown as NSString
        let fullRange = NSRange(location: 0, length: nsMarkdown.length)
        let matches = Self.markdownHeadingRegex.matches(in: markdown, range: fullRange)

        guard matches.count > 1 else {
            pages = []
            currentPage = 0
            currentPageHTML = ""
            return
        }

        var newPages: [String] = []
        var cursor = markdown.startIndex

        for (i, match) in matches.enumerated() {
            guard let pos = Range(match.range, in: markdown) else { continue }
            if i == 0 {
                if pos.lowerBound > markdown.startIndex {
                    // Content before first heading — include in first page
                    cursor = markdown.startIndex
                }
                continue
            }
            let page = String(markdown[cursor..<pos.lowerBound])
            if !page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newPages.append(page)
            }
            cursor = pos.lowerBound
        }
        let lastPage = String(markdown[cursor...])
        if !lastPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newPages.append(lastPage)
        }

        pages = newPages
        currentPage = 0
        currentPageHTML = pages.first ?? ""
    }

    private func goToPage(_ page: Int) {
        guard !pages.isEmpty, page >= 0, page < pages.count else { return }
        currentPage = page
        currentPageHTML = pages[page]
    }

    /// Find which page contains a heading ID and navigate to it.
    private func navigateToHeading(_ headingID: String) {
        guard !pages.isEmpty else {
            tocScrollTarget = headingID
            return
        }
        // Find which page contains this heading
        for (i, page) in pages.enumerated() {
            let pageHeadings = Self.parseHeadings(page)
            if pageHeadings.contains(where: { $0.id == headingID }) {
                if currentPage != i {
                    goToPage(i)
                    // Delay scroll to allow page to render
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.tocScrollTarget = headingID
                    }
                } else {
                    tocScrollTarget = headingID
                }
                return
            }
        }
        // Fallback
        tocScrollTarget = headingID
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    private func updateSiblingFiles() {
        guard let fileURL else { siblingFiles = []; return }
        let dir = fileURL.deletingLastPathComponent()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            siblingFiles = []
            return
        }
        siblingFiles = contents
            .filter { Self.markdownExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func startWatching(_ url: URL) {
        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url) { currentURL in
            // Update fileURL if the file was renamed
            if currentURL != self.fileURL {
                self.fileURL = currentURL
            }
            // Re-check file size on reload to prevent OOM
            if let attrs = try? FileManager.default.attributesOfItem(atPath: currentURL.path),
               let size = attrs[.size] as? UInt64,
               size > Self.maxFileSize { return }
            let newContent = HTMLBuilder.readFileWithFallback(url: currentURL)
            // If sandbox blocks re-reading after atomic save, skip silently
            if newContent.hasPrefix("# Unable to read file") { return }
            if newContent != self.markdown {
                let oldContent = self.markdown
                self.markdown = newContent
                // Compute diff and show highlights
                let hunks = MarkdownRenderer.lineDiff(old: oldContent, new: newContent)
                self.diffHunks = MarkdownRenderer.renderHunkText(hunks: hunks)
                self.showDiffHighlights = true
                self.applyDiffTrigger += 1
                self.showDiffToast()
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

struct ClearHighlightsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ZoomInActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ZoomOutActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ZoomResetActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FindNextActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FindPrevActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
struct CopyRichTextActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
struct CompareActionKey: FocusedValueKey {
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
    var clearHighlightsAction: (() -> Void)? {
        get { self[ClearHighlightsActionKey.self] }
        set { self[ClearHighlightsActionKey.self] = newValue }
    }
    var zoomInAction: (() -> Void)? {
        get { self[ZoomInActionKey.self] }
        set { self[ZoomInActionKey.self] = newValue }
    }
    var zoomOutAction: (() -> Void)? {
        get { self[ZoomOutActionKey.self] }
        set { self[ZoomOutActionKey.self] = newValue }
    }
    var zoomResetAction: (() -> Void)? {
        get { self[ZoomResetActionKey.self] }
        set { self[ZoomResetActionKey.self] = newValue }
    }
    var findNextAction: (() -> Void)? {
        get { self[FindNextActionKey.self] }
        set { self[FindNextActionKey.self] = newValue }
    }
    var findPrevAction: (() -> Void)? {
        get { self[FindPrevActionKey.self] }
        set { self[FindPrevActionKey.self] = newValue }
    }
    var copyRichTextAction: (() -> Void)? {
        get { self[CopyRichTextActionKey.self] }
        set { self[CopyRichTextActionKey.self] = newValue }
    }
    var compareAction: (() -> Void)? {
        get { self[CompareActionKey.self] }
        set { self[CompareActionKey.self] = newValue }
    }
}

/// Pill-style bar showing active search highlights with push/pop stack.
struct SearchTermsBar: View {
    private static let slotColors: [Color] = [
        Color(red: 1.0, green: 0.83, blue: 0.24),
        Color(red: 0.35, green: 0.65, blue: 1.0),
        Color(red: 0.25, green: 0.73, blue: 0.31),
        Color(red: 0.94, green: 0.53, blue: 0.24),
        Color(red: 0.74, green: 0.55, blue: 1.0),
    ]

    let terms: [(term: String, slot: Int, count: Int, current: Int)]
    let stack: [[String]]
    @Binding var caseSensitive: Bool
    @Binding var wholeWord: Bool
    let onTap: (String) -> Void
    let onRemove: (String) -> Void
    let onPush: () -> Void
    let onPop: () -> Void
    let onRestore: (Int) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !terms.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(terms.enumerated()), id: \.element.term) { _, entry in
                        HStack(spacing: 2) {
                            Button {
                                onTap(entry.term)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Self.slotColors[entry.slot % Self.slotColors.count])
                                        .frame(width: 8, height: 8)
                                    Text(entry.term)
                                        .lineLimit(1)
                                    if entry.current > 0 {
                                        Text("\(entry.current)/\(entry.count)")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(entry.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Button {
                                onRemove(entry.term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    Button {
                        onPush()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Save to stack")
                    if !stack.isEmpty {
                        Button {
                            onPop()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Restore from stack")
                    }
                    Divider().frame(height: 12)
                    Button {
                        caseSensitive.toggle()
                    } label: {
                        Text("Aa")
                            .font(.system(size: 10, weight: caseSensitive ? .bold : .regular))
                            .foregroundStyle(caseSensitive ? .primary : .tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Case Sensitive")
                    Button {
                        wholeWord.toggle()
                    } label: {
                        Text("W")
                            .font(.system(size: 10, weight: wholeWord ? .bold : .regular))
                            .foregroundStyle(wholeWord ? .primary : .tertiary)
                            .underline(wholeWord)
                    }
                    .buttonStyle(.plain)
                    .help("Whole Word")
                    Divider().frame(height: 12)
                    Button("Clear All") {
                        onClearAll()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            if !stack.isEmpty {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    ForEach(Array(stack.enumerated()), id: \.offset) { index, entry in
                        Button {
                            onRestore(index)
                        } label: {
                            Text(entry.joined(separator: ", "))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if terms.isEmpty && !stack.isEmpty {
                        Button {
                            onPop()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Restore from stack")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }
    }
}

/// Extracts words from markdown text for search suggestions.
enum WordExtractor {
    private static let stopWords: Set<String> = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "it",
        "for", "not", "on", "with", "as", "you", "do", "at", "this", "but",
        "by", "from", "they", "we", "or", "an", "will", "all", "would",
        "there", "their", "what", "so", "up", "out", "if", "about", "who",
        "which", "when", "can", "like", "no", "just", "him", "know", "take",
        "into", "your", "some", "could", "them", "than", "then", "now",
        "its", "over", "also", "after", "use", "how", "our", "any", "these",
        "most", "is", "are", "was", "were", "been", "has", "had", "does",
        "may", "should", "must", "very", "such", "more", "other", "only",
    ]

    static func extractWords(from markdown: String, limit: Int = 200) -> [String] {
        var frequency: [String: Int] = [:]
        markdown.enumerateSubstrings(in: markdown.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word else { return }
            let lower = word.lowercased()
            if lower.count < 3 && lower.allSatisfy({ $0.isASCII }) { return }
            if lower.count > 50 { return }
            if stopWords.contains(lower) { return }
            if lower.allSatisfy({ $0.isNumber }) { return }
            frequency[lower, default: 0] += 1
        }
        return frequency
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map { $0.key }
    }
}

/// Custom compact slider without system rendering artifacts.
struct CompactSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0.05) {
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        GeometryReader { geo in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbX = fraction * geo.size.width

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 4)
                // Filled track
                Capsule()
                    .fill(.primary.opacity(0.5))
                    .frame(width: max(4, thumbX), height: 4)
                // Thumb
                Circle()
                    .fill(.primary.opacity(0.85))
                    .frame(width: 12, height: 12)
                    .offset(x: thumbX - 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = max(0, min(1, drag.location.x / geo.size.width))
                        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                        value = (raw / step).rounded() * step
                        value = max(range.lowerBound, min(range.upperBound, value))
                    }
            )
        }
        .frame(height: 14)
    }
}

/// VS Code-style outline sidebar showing heading hierarchy.
/// Draggable handle to resize the TOC sidebar.
struct ResizableHandle: View {
    @Binding var width: Double

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(width: 6)
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        width = max(120, min(500, width + value.translation.width))
                    }
            )
            .overlay(Divider())
    }
}

/// Vertical resize handle between FILES and OUTLINE sections.
struct VerticalResizeHandle: View {
    @Binding var height: Double
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @GestureState private var dragStartHeight: Double?

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(height: 6)
            .cursor(.resizeUpDown)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragStartHeight) { _, state, _ in
                        if state == nil { state = height }
                    }
                    .onChanged { value in
                        let start = dragStartHeight ?? height
                        height = max(Double(minHeight), min(Double(maxHeight), start + value.translation.height))
                    }
            )
            .overlay(Divider())
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

/// Collapsible section header for sidebar panels (FILES, OUTLINE).
struct SidebarSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Sidebar panel listing sibling markdown files in the same directory.
struct FilesSidebar: NSViewRepresentable {
    let files: [URL]
    let currentFile: URL?
    let onSelect: (URL) -> Void

    func makeCoordinator() -> FilesCoordinator {
        FilesCoordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(FilesCoordinator.tableClicked(_:))

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.files = files
        context.coordinator.currentFile = currentFile
        tableView.reloadData()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.onSelect = onSelect
        let changed = coord.files.count != files.count || coord.currentFile != currentFile
            || zip(coord.files, files).contains(where: { $0 != $1 })
        if changed {
            coord.files = files
            coord.currentFile = currentFile
            coord.tableView?.reloadData()
        }
    }

    class FilesCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var files: [URL] = []
        var currentFile: URL?
        var onSelect: (URL) -> Void
        weak var tableView: NSTableView?

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func numberOfRows(in tableView: NSTableView) -> Int { files.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cellID = NSUserInterfaceItemIdentifier("FileCell")
            let tf: NSTextField
            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
                tf = reused
            } else {
                tf = NSTextField(labelWithString: "")
                tf.identifier = cellID
                tf.lineBreakMode = .byTruncatingTail
                tf.drawsBackground = false
                tf.isBezeled = false
                tf.isEditable = false
            }
            guard row < files.count else { return tf }
            let file = files[row]
            let isCurrent = file == currentFile
            let name = file.deletingPathExtension().lastPathComponent

            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 12
            para.lineBreakMode = .byTruncatingTail

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: isCurrent ? .semibold : .regular),
                .foregroundColor: isCurrent ? NSColor.controlAccentColor : NSColor.labelColor,
                .paragraphStyle: para
            ]
            tf.attributedStringValue = NSAttributedString(string: name, attributes: attrs)
            return tf
        }

        @objc func tableClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < files.count else { return }
            onSelect(files[row])
        }
    }
}

struct TOCSidebar: NSViewRepresentable {
    let headings: [(level: Int, text: String, id: String)]
    let zoomLevel: Double
    let width: Double
    let onSelect: (String) -> Void

    static let dotColors: [NSColor] = [
        NSColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1),
        NSColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1),
        NSColor(red: 0.25, green: 0.72, blue: 0.35, alpha: 1),
        NSColor(red: 0.93, green: 0.60, blue: 0.15, alpha: 1),
        NSColor(red: 0.62, green: 0.42, blue: 0.90, alpha: 1),
        NSColor(red: 0.15, green: 0.72, blue: 0.72, alpha: 1),
    ]

    func makeCoordinator() -> TOCCoordinator {
        TOCCoordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(TOCCoordinator.tableClicked(_:))

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.tableView = tableView
        context.coordinator.headings = headings
        context.coordinator.zoomLevel = zoomLevel
        context.coordinator.rebuildCache()
        tableView.reloadData()

        container.setFrameSize(NSSize(width: max(120, min(500, width)), height: 400))
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coord = context.coordinator
        coord.onSelect = onSelect
        if coord.headings.count != headings.count || coord.zoomLevel != zoomLevel {
            coord.headings = headings
            coord.zoomLevel = zoomLevel
            coord.rebuildCache()
            coord.tableView?.reloadData()
        }
    }

    class TOCCoordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var headings: [(level: Int, text: String, id: String)] = []
        var zoomLevel: Double = 1.0
        var onSelect: (String) -> Void
        weak var tableView: NSTableView?
        /// Pre-built attributed strings for each heading, rebuilt on data change.
        var cachedStrings: [NSAttributedString] = []

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        private static let dotSymbols = ["●", "●", "○", "○", "◦", "◦"]

        func rebuildCache() {
            cachedStrings = headings.map { heading in
                let level = min(heading.level - 1, 5)
                let indent = String(repeating: "    ", count: level)
                let dot = Self.dotSymbols[level]
                let color = TOCSidebar.dotColors[level]
                let fontSize = (heading.level <= 2 ? 12.0 : 11.0) * zoomLevel
                let weight: NSFont.Weight = heading.level <= 1 ? .semibold : .regular
                let textColor: NSColor = heading.level <= 2 ? .labelColor : .secondaryLabelColor

                let para = NSMutableParagraphStyle()
                para.firstLineHeadIndent = CGFloat(level * 12) + 12
                para.lineBreakMode = .byTruncatingTail

                let str = NSMutableAttributedString()
                str.append(NSAttributedString(string: indent))
                str.append(NSAttributedString(string: dot + " ", attributes: [
                    .foregroundColor: color,
                    .font: NSFont.systemFont(ofSize: fontSize * 0.8)
                ]))
                str.append(NSAttributedString(string: heading.text, attributes: [
                    .foregroundColor: textColor,
                    .font: NSFont.systemFont(ofSize: fontSize, weight: weight)
                ]))
                str.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: str.length))
                return str
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { headings.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cellID = NSUserInterfaceItemIdentifier("TOCCell")
            let tf: NSTextField
            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
                tf = reused
            } else {
                tf = NSTextField(labelWithString: "")
                tf.identifier = cellID
                tf.lineBreakMode = .byTruncatingTail
                tf.drawsBackground = false
                tf.isBezeled = false
                tf.isEditable = false
            }
            if row < cachedStrings.count {
                tf.attributedStringValue = cachedStrings[row]
            }
            return tf
        }

        @objc func tableClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < headings.count else { return }
            onSelect(headings[row].id)
        }
    }
}

/// Horizontal flow layout that wraps items to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
