import Cocoa
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    var webView: WKWebView!

    override func loadView() {
        webView = WKWebView()
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        self.view = webView
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private static let maxFileSize: UInt64 = 10 * 1024 * 1024

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size > Self.maxFileSize {
            let sizeMB = String(format: "%.1f", Double(size) / 1_048_576)
            let html = buildHTML(from: "# File too large\n\nThis file is \(sizeMB) MB. Maximum supported size is 10 MB.")
            webView.loadHTMLString(html, baseURL: nil)
            handler(nil)
            return
        }
        let markdown = Self.readFileWithFallback(url: url)
        let html = buildHTML(from: markdown)
        webView.loadHTMLString(html, baseURL: nil)
        handler(nil)
    }

    private static func readFileWithFallback(url: URL) -> String {
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .shiftJIS, .utf16, .ascii]
        for encoding in encodings {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                return content
            }
        }
        return "# Unable to read file\n\nThis file could not be decoded as text."
    }

    private static let inlineMathRegex = try! NSRegularExpression(pattern: "\\$[^\\s$].*?[^\\s$]\\$|\\$[^\\s$]\\$", options: [])

    private static func containsInlineMath(_ html: String) -> Bool {
        let range = NSRange(html.startIndex..., in: html)
        return inlineMathRegex.firstMatch(in: html, range: range) != nil
    }

    nonisolated(unsafe) private static var _resourceCache: [String: String] = [:]

    private static func cachedResource(_ name: String, type: String) -> String {
        let key = "\(name).\(type)"
        if let cached = _resourceCache[key] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: type),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        _resourceCache[key] = content
        return content
    }

    nonisolated(unsafe) private static var cachedStyleBlock: String?
    nonisolated(unsafe) private static var cachedBaseHead: String?
    nonisolated(unsafe) private static var cachedMermaidScript: String?
    nonisolated(unsafe) private static var cachedKatexHead: String?

    private static func styleBlock() -> String {
        if let cached = cachedStyleBlock { return cached }
        let githubCSS = cachedResource("github.min", type: "css")
        let githubDarkCSS = cachedResource("github-dark.min", type: "css")
        let modsCSS = cachedResource("mods", type: "css")
        let block = """
        <style>
        \(githubCSS)
        @media (prefers-color-scheme: dark) { \(githubDarkCSS) }
        \(modsCSS)
        </style>
        """
        cachedStyleBlock = block
        return block
    }

    private static func baseHead() -> String {
        if let cached = cachedBaseHead { return cached }
        let head = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(styleBlock())
        <script>\(cachedResource("highlight.min", type: "js"))</script>
        """
        cachedBaseHead = head
        return head
    }

    private static func mermaidScript() -> String {
        if let cached = cachedMermaidScript { return cached }
        let s = "<script>\(cachedResource("mermaid.min", type: "js"))</script>\n"
        cachedMermaidScript = s
        return s
    }

    private static func katexHead() -> String {
        if let cached = cachedKatexHead { return cached }
        let s = """
        <style>\(cachedResource("katex.min", type: "css"))</style>
        <script>\(cachedResource("katex.min", type: "js"))</script>
        <script>\(cachedResource("katex-auto-render.min", type: "js"))</script>
        """
        cachedKatexHead = s
        return s
    }

    private static let footerScript = """
    <script>
    if (typeof mermaid !== 'undefined') {
        mermaid.initialize({ startOnLoad: false, theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default' });
        var mermaidBlocks = document.querySelectorAll('pre code.language-mermaid');
        mermaidBlocks.forEach(function(block) {
            var pre = block.parentElement;
            var div = document.createElement('div');
            div.className = 'mermaid';
            div.textContent = block.textContent;
            pre.replaceWith(div);
        });
        if (mermaidBlocks.length > 0) { mermaid.run(); }
    }
    document.querySelectorAll('pre code').forEach(function(block) {
        if (!block.classList.contains('language-math')) { hljs.highlightElement(block); }
    });
    document.querySelectorAll('input[type="checkbox"]').forEach(function(cb) { cb.disabled = true; });
    if (typeof katex !== 'undefined') {
        document.querySelectorAll('pre code.language-math').forEach(function(block) {
            var pre = block.parentElement;
            var div = document.createElement('div');
            div.className = 'math-block';
            try { katex.render(block.textContent, div, { displayMode: true, throwOnError: false }); }
            catch(e) { div.textContent = block.textContent; }
            pre.replaceWith(div);
        });
        if (typeof renderMathInElement !== 'undefined') {
            renderMathInElement(document.getElementById('content'), {
                delimiters: [{left: '$$', right: '$$', display: true}, {left: '$', right: '$', display: false}],
                throwOnError: false
            });
        }
    }
    </script>
    """

    private func buildHTML(from markdown: String) -> String {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)

        let needsMermaid = bodyHTML.contains("language-mermaid")
        let needsMath = bodyHTML.contains("language-math") || bodyHTML.contains("$$") || Self.containsInlineMath(bodyHTML)

        var html = Self.baseHead()
        if needsMath { html += Self.katexHead() }
        if needsMermaid { html += Self.mermaidScript() }
        html += "</head>\n<body>\n<div id=\"content\">\(bodyHTML)</div>\n"
        html += Self.footerScript
        html += "</body>\n</html>"
        return html
    }

}
