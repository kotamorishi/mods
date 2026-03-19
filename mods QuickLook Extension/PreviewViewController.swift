import Cocoa
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    var webView: WKWebView!
    var pendingPostLoadJS: String = ""

    override func loadView() {
        webView = WKWebView(frame: .zero, configuration: HTMLBuilder.webViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        self.view = webView
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !pendingPostLoadJS.isEmpty {
            webView.evaluateJavaScript(pendingPostLoadJS)
            pendingPostLoadJS = ""
        }
    }

    private static let maxFileSize: UInt64 = 10 * 1024 * 1024

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size > Self.maxFileSize {
            let sizeMB = String(format: "%.1f", Double(size) / 1_048_576)
            let bodyHTML = MarkdownRenderer.renderToHTML("# File too large\n\nThis file is \(sizeMB) MB. Maximum supported size is 10 MB.")
            webView.loadHTMLString(HTMLBuilder.buildHTML(bodyHTML: bodyHTML), baseURL: nil)
            handler(nil)
            return
        }
        let markdown = HTMLBuilder.readFileWithFallback(url: url)
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)
        pendingPostLoadJS = HTMLBuilder.conditionalJS(for: bodyHTML)
        webView.loadHTMLString(HTMLBuilder.buildHTML(bodyHTML: bodyHTML), baseURL: nil)
        handler(nil)
    }
}
