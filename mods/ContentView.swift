import SwiftUI
import UniformTypeIdentifiers

struct StartView: View {
    @State private var fileURL: URL?
    @State private var markdown: String = ""
    @State private var zoomLevel: Double = 1.0

    var body: some View {
        Group {
            if markdown.isEmpty {
                Text("Drop a markdown file or use File > Open")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownWebView(markdown: markdown, zoomLevel: zoomLevel)
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

    private static let maxFileSize: UInt64 = 10 * 1024 * 1024 // 10 MB

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

        self.markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? "Failed to load file."
    }
}
