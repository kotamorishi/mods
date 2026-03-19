import SwiftUI
import UniformTypeIdentifiers

struct StartView: View {
    @State private var fileURL: URL?
    @State private var markdown: String = ""
    @State private var zoomLevel: Double = 1.0
    @State private var fileWatcher: FileWatcher?
    @State private var findTrigger: Int = 0

    var body: some View {
        Group {
            if fileURL == nil {
                Text("Drop a markdown file or use File > Open")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownWebView(markdown: markdown, zoomLevel: zoomLevel, findTrigger: findTrigger)
            }
        }
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
        .onOpenURL { url in
            loadURL(url)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    DispatchQueue.main.async {
                        loadURL(url)
                    }
                }
            }
            return true
        }
        .onDisappear {
            fileWatcher?.stop()
        }
    }

    private func performFind() {
        findTrigger += 1
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadURL(url)
        }
    }

    private static let maxFileSize: UInt64 = 10 * 1024 * 1024

    private func loadURL(_ url: URL) {
        self.fileURL = url
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
        fileWatcher = FileWatcher(url: url) { [self] in
            let newContent = HTMLBuilder.readFileWithFallback(url: url)
            if newContent != self.markdown {
                self.markdown = newContent
            }
        }
        fileWatcher?.start()
    }
}

/// Watches a file for modifications using GCD dispatch source.
final class FileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @MainActor @escaping () -> Void) {
        self.url = url
        self.onChange = { DispatchQueue.main.async { onChange() } }
    }

    func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [onChange] in
            onChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
