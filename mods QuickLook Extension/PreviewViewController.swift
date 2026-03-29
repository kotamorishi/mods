import Cocoa
import QuickLookUI
import WebKit

@MainActor
class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    var pendingPostLoadJS: String = ""
    private var handlerRegistered = false

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.isElementFullscreenEnabled = false
        let controller = WKUserContentController()
        let highlightJS = HTMLBuilder.cachedResource("highlight.min", type: "js")
        if !highlightJS.isEmpty {
            controller.addUserScript(WKUserScript(source: highlightJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        controller.addUserScript(WKUserScript(source: HTMLBuilder.postProcessScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.add(self, name: "loadImage")
        config.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
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
            DispatchQueue.main.async { [self] in
                pendingPostLoadJS = ""
                webView.loadHTMLString(html, baseURL: nil)
            }
            handler(nil)
            return
        }
        let markdown = HTMLBuilder.readFileWithFallback(url: url)
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
        let postLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
        let html = HTMLBuilder.buildHTML(bodyHTML: bodyHTML)
        DispatchQueue.main.async { [self] in
            pendingPostLoadJS = postLoadJS
            webView.loadHTMLString(html, baseURL: nil)
        }
        handler(nil)
    }
}
