import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentMarkdown: String = ""
        var isInitialLoadDone = false
        var lastHTML: String = ""

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }

        /// Recover from WebKit process crash by reloading the last content.
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
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
        let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
        context.coordinator.lastHTML = html
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
    }

    /// Fast content update: swap #content innerHTML via JS and re-run post-processing.
    private func updateContentViaJS(webView: WKWebView) {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)

        var js = "document.getElementById('content').innerHTML = \(HTMLBuilder.jsonEncode(bodyHTML));\n"

        if HTMLBuilder.needsMermaid(bodyHTML) {
            js += """
            if (typeof mermaid === 'undefined') {
                var s = document.createElement('script');
                s.textContent = \(HTMLBuilder.jsonEncode(HTMLBuilder.cachedResource("mermaid.min", type: "js")));
                document.head.appendChild(s);
            }

            """
        }
        if HTMLBuilder.needsMath(bodyHTML) {
            js += """
            if (typeof katex === 'undefined') {
                var ks = document.createElement('style');
                ks.textContent = \(HTMLBuilder.jsonEncode(HTMLBuilder.cachedResource("katex.min", type: "css")));
                document.head.appendChild(ks);
                var k1 = document.createElement('script');
                k1.textContent = \(HTMLBuilder.jsonEncode(HTMLBuilder.cachedResource("katex.min", type: "js")));
                document.head.appendChild(k1);
                var k2 = document.createElement('script');
                k2.textContent = \(HTMLBuilder.jsonEncode(HTMLBuilder.cachedResource("katex-auto-render.min", type: "js")));
                document.head.appendChild(k2);
            }

            """
        }

        js += "window.scrollTo(0, 0);\n"
        js += "window.__modsPostProcess();\n"

        webView.evaluateJavaScript(js)
    }
}
