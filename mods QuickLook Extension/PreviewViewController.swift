import Cocoa
import QuickLookUI
import WebKit

@MainActor
class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    var pendingPostLoadJS: String = ""

    override func loadView() {
        webView = WKWebView(frame: .zero, configuration: HTMLBuilder.webViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "loadImage")
        self.view = webView
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "loadImage",
              let body = message.body as? [String: String],
              let id = body["id"],
              let src = body["src"] else { return }
        TrustedImageDomains.handleLoadImage(id: id, src: src, webView: webView)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .other {
            return .allow
        }
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

    nonisolated private static let maxFileSize: UInt64 = 10 * 1024 * 1024

    nonisolated func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size > Self.maxFileSize {
            let sizeMB = String(format: "%.1f", Double(size) / 1_048_576)
            let bodyHTML = MarkdownRenderer.renderToHTML("# File too large\n\nThis file is \(sizeMB) MB. Maximum supported size is 10 MB.")
            let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
            MainActor.assumeIsolated {
                webView.loadHTMLString(html, baseURL: nil)
            }
            handler(nil)
            return
        }
        let markdown = HTMLBuilder.readFileWithFallback(url: url)
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
        let postLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
        let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
        MainActor.assumeIsolated {
            pendingPostLoadJS = postLoadJS
            webView.loadHTMLString(html, baseURL: nil)
        }
        handler(nil)
    }
}
