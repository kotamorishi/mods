import SwiftUI

struct ContentView: View {
    let document: MarkdownDocument
    @State private var zoomLevel: Double = 1.0

    var body: some View {
        MarkdownWebView(markdown: document.text, zoomLevel: zoomLevel)
            .frame(minWidth: 400, minHeight: 300)
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
    }
}
