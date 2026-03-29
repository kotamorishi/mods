import SwiftUI
import UniformTypeIdentifiers

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
                Button("Table of Contents") {
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
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                                    .foregroundStyle(.orange.opacity(0.6))
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.orange.opacity(0.1))
                            )
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
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                                    .foregroundStyle(.blue.opacity(0.6))
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.blue.opacity(0.1))
                            )
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

/// File viewer window: shows rendered markdown for a single file.
struct FileView: View {
    let initialURL: URL
    @Environment(\.openWindow) private var openWindow
    @State private var fileURL: URL?
    @State private var markdown: String = ""
    @AppStorage("zoomLevel") private var zoomLevel: Double = 1.0
    @State private var fileWatcher: FileWatcher?
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var search = SearchState()
    @State private var activeSearchTerms: [(term: String, slot: Int, count: Int, current: Int)] = []
    @State private var searchStack: [[String]] = []
    @State private var suggestionWords: [String] = []
    @State private var printTrigger: Int = 0
    @State private var exportPDFTrigger: Int = 0
    @State private var tocScrollTarget: String = ""
    @AppStorage("showTOC") private var showTOC: Bool = false
    @AppStorage("tocWidth") private var tocWidth: Double = 220

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

    var body: some View {
        mainContent
            .onOpenURL(perform: handleOpenURL)
            .onDisappear { fileWatcher?.stop() }
            .onAppear { loadURL(initialURL) }
    }

    private var mainContent: some View {
        mainLayout
            .focusedSceneValue(\.openFileAction, openFile)
            .focusedSceneValue(\.findAction, performFind)
            .focusedSceneValue(\.printAction, performPrint)
            .focusedSceneValue(\.exportPDFAction, performExportPDF)
            .focusedSceneValue(\.tocAction, toggleTOC)
            .focusedSceneValue(\.clearHighlightsAction, clearHighlights)
            .focusedSceneValue(\.zoomInAction, performZoomIn)
            .focusedSceneValue(\.zoomOutAction, performZoomOut)
            .focusedSceneValue(\.zoomResetAction, performZoomReset)
            .focusedSceneValue(\.findNextAction, performFindNext)
            .focusedSceneValue(\.findPrevAction, performFindPrev)
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            contentArea
            bottomBar
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
        .onChange(of: markdown) { updateSuggestions() }
    }

    private var contentArea: some View {
        HStack(spacing: 0) {
            if showTOC && !headings.isEmpty {
                TOCSidebar(headings: headings, zoomLevel: zoomLevel, width: tocWidth) { heading in
                    tocScrollTarget = heading
                }
                ResizableHandle(width: $tocWidth)
            }
            markdownWebView
        }
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
        MarkdownWebView(markdown: markdown, zoomLevel: zoomLevel, search: search, activeSearchTerms: $activeSearchTerms, searchStack: $searchStack, printTrigger: printTrigger, exportPDFTrigger: exportPDFTrigger, tocScrollTarget: tocScrollTarget)
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
            Button { showTOC.toggle() } label: { Image(systemName: "list.bullet") }
                .help("Toggle Outline")
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
    private func toggleTOC() { showTOC.toggle() }
    private func clearHighlights() { search.clearTrigger += 1 }
    private func performZoomIn() { zoomLevel = min(5.0, zoomLevel + 0.1) }
    private func performZoomOut() { zoomLevel = max(0.25, zoomLevel - 0.1) }
    private func performZoomReset() { zoomLevel = 1.0 }
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
            // Re-check file size on reload to prevent OOM
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64,
               size > Self.maxFileSize { return }
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

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

struct TOCSidebar: View {
    let headings: [(level: Int, text: String)]
    let zoomLevel: Double
    let width: Double
    let onSelect: (String) -> Void

    private static let dotSizes: [CGFloat] = [8, 7, 6, 5, 4, 4]
    private static let dotColors: [Color] = [
        Color(red: 0.85, green: 0.25, blue: 0.25),  // red
        Color(red: 0.20, green: 0.55, blue: 0.95),  // blue
        Color(red: 0.25, green: 0.72, blue: 0.35),  // green
        Color(red: 0.93, green: 0.60, blue: 0.15),  // orange
        Color(red: 0.62, green: 0.42, blue: 0.90),  // purple
        Color(red: 0.15, green: 0.72, blue: 0.72),  // teal
    ]

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
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Self.dotColors[min(heading.level - 1, 5)])
                                    .frame(width: Self.dotSizes[min(heading.level - 1, 5)],
                                           height: Self.dotSizes[min(heading.level - 1, 5)])
                                Text(heading.text)
                                    .font(.system(size: (heading.level <= 2 ? 12 : 11) * zoomLevel,
                                                  weight: heading.level <= 1 ? .semibold : .regular))
                                    .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat((heading.level - 1) * 12))
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
        .frame(width: max(120, min(500, width)))
        .background(.background)
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
