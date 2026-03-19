import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double
    let findTrigger: Int
    let printTrigger: Int

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentMarkdown: String = ""
        var isInitialLoadDone = false
        var lastHTML: String = ""
        var pendingPostLoadJS: String = ""
        var lastFindTrigger: Int = 0
        var lastPrintTrigger: Int = 0

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Allow initial HTML string load and about:blank
            if navigationAction.navigationType == .other {
                return .allow
            }
            // All clicks open in default browser — never navigate inside WebView
            if let url = navigationAction.request.url,
               url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !pendingPostLoadJS.isEmpty {
                webView.evaluateJavaScript(pendingPostLoadJS)
                pendingPostLoadJS = ""
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if !lastHTML.isEmpty {
                webView.loadHTMLString(lastHTML, baseURL: nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: HTMLBuilder.webViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator
        context.coordinator.currentMarkdown = markdown
        context.coordinator.isInitialLoadDone = true
        context.coordinator.lastFindTrigger = findTrigger
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
        let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
        context.coordinator.lastHTML = html
        context.coordinator.pendingPostLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoomLevel

        if context.coordinator.currentMarkdown != markdown {
            context.coordinator.currentMarkdown = markdown

            if context.coordinator.isInitialLoadDone {
                updateContentViaJS(webView: webView)
            } else {
                let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
                webView.loadHTMLString(HTMLBuilder.buildHTML(bodyHTML: bodyHTML), baseURL: nil)
                context.coordinator.isInitialLoadDone = true
            }
        }

        // Toggle find bar
        if context.coordinator.lastFindTrigger != findTrigger {
            context.coordinator.lastFindTrigger = findTrigger
            webView.evaluateJavaScript("window.__modsToggleFind();")
        }

        // Print
        if context.coordinator.lastPrintTrigger != printTrigger {
            context.coordinator.lastPrintTrigger = printTrigger
            webView.printOperation(with: .shared).runModal(for: webView.window ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    private func updateContentViaJS(webView: WKWebView) {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)

        var js = "document.getElementById('content').innerHTML = \(HTMLBuilder.jsonEncode(bodyHTML));\n"
        js += "window.scrollTo(0, 0);\n"
        js += HTMLBuilder.conditionalJS(for: bodyHTML)

        webView.evaluateJavaScript(js)
    }
}
