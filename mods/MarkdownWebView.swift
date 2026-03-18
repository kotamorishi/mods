import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double

    // MARK: - Shared WKWebViewConfiguration (created once, reused)

    nonisolated(unsafe) private static var sharedConfig: WKWebViewConfiguration?

    /// Create a WKWebViewConfiguration with highlight.js pre-injected as a user script.
    /// This avoids re-parsing 127KB of JS on every HTML load.
    private static func configuration() -> WKWebViewConfiguration {
        if let config = sharedConfig { return config }
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // Inject highlight.js once — available for all subsequent page loads
        let highlightJS = cachedResource("highlight.min", type: "js")
        if !highlightJS.isEmpty {
            let script = WKUserScript(source: highlightJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            controller.addUserScript(script)
        }

        config.userContentController = controller
        sharedConfig = config
        return config
    }

    // MARK: - CSS (cached)

    nonisolated(unsafe) private static var cachedStyleBlock: String?

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

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentMarkdown: String = ""

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.configuration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator
        context.coordinator.currentMarkdown = markdown
        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoomLevel

        // Reload content if markdown changed
        if context.coordinator.currentMarkdown != markdown {
            context.coordinator.currentMarkdown = markdown
            let html = buildHTML()
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    // MARK: - HTML Builder

    /// The footer script that runs after content is loaded.
    /// highlight.js is already injected via WKUserScript, so hljs is available globally.
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

    nonisolated(unsafe) private static var cachedBaseHead: String?
    nonisolated(unsafe) private static var cachedMermaidScript: String?
    nonisolated(unsafe) private static var cachedKatexHead: String?

    /// Base <head> with CSS only (highlight.js is now a WKUserScript). Built once.
    private static func baseHead() -> String {
        if let cached = cachedBaseHead { return cached }
        let head = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(styleBlock())
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

    private func buildHTML() -> String {
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

    // MARK: - Helpers

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
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        _resourceCache[key] = content
        return content
    }
}
