import Foundation
import WebKit

/// Shared HTML template builder used by both the main app and QuickLook extension.
/// Handles resource caching, CSS/JS assembly, WKWebView configuration, and content detection.
enum HTMLBuilder {
    // MARK: - Resource Cache

    nonisolated(unsafe) private static var _resourceCache: [String: String] = [:]

    static func cachedResource(_ name: String, type: String) -> String {
        let key = "\(name).\(type)"
        if let cached = _resourceCache[key] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: type),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        _resourceCache[key] = content
        return content
    }

    // MARK: - WKWebView Configuration

    nonisolated(unsafe) private static var _sharedConfig: WKWebViewConfiguration?

    /// Shared configuration with highlight.js + post-processing injected via WKUserScript.
    static func webViewConfiguration() -> WKWebViewConfiguration {
        if let config = _sharedConfig { return config }
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        let highlightJS = cachedResource("highlight.min", type: "js")
        if !highlightJS.isEmpty {
            controller.addUserScript(WKUserScript(source: highlightJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        controller.addUserScript(WKUserScript(source: postProcessScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        config.userContentController = controller
        _sharedConfig = config
        return config
    }

    // MARK: - Cached HTML Fragments

    nonisolated(unsafe) private static var _styleBlock: String?
    nonisolated(unsafe) private static var _baseHead: String?
    nonisolated(unsafe) private static var _mermaidScript: String?
    nonisolated(unsafe) private static var _katexHead: String?

    static func styleBlock() -> String {
        if let cached = _styleBlock { return cached }
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
        _styleBlock = block
        return block
    }

    /// Shell page head: CSS only (JS via WKUserScript).
    static func baseHead() -> String {
        if let cached = _baseHead { return cached }
        let head = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(styleBlock())
        </head>
        <body>
        <div id="content">
        """
        _baseHead = head
        return head
    }

    static func mermaidScript() -> String {
        if let cached = _mermaidScript { return cached }
        let s = "<script>\(cachedResource("mermaid.min", type: "js"))</script>\n"
        _mermaidScript = s
        return s
    }

    static func katexHead() -> String {
        if let cached = _katexHead { return cached }
        let s = """
        <style>\(cachedResource("katex.min", type: "css"))</style>
        <script>\(cachedResource("katex.min", type: "js"))</script>
        <script>\(cachedResource("katex-auto-render.min", type: "js"))</script>
        """
        _katexHead = s
        return s
    }

    // MARK: - Post-Processing Script

    /// Injected via WKUserScript. Defines __modsPostProcess() and calls it on initial load.
    static let postProcessScript = """
    window.__modsPostProcess = function() {
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
    };
    window.__modsPostProcess();
    """

    // MARK: - Content Detection

    private static let inlineMathRegex = try! NSRegularExpression(pattern: "\\$[^\\s$].*?[^\\s$]\\$|\\$[^\\s$]\\$", options: [])

    static func containsInlineMath(_ html: String) -> Bool {
        let range = NSRange(html.startIndex..., in: html)
        return inlineMathRegex.firstMatch(in: html, range: range) != nil
    }

    static func needsMath(_ bodyHTML: String) -> Bool {
        bodyHTML.contains("language-math") || bodyHTML.contains("$$") || containsInlineMath(bodyHTML)
    }

    static func needsMermaid(_ bodyHTML: String) -> Bool {
        bodyHTML.contains("language-mermaid")
    }

    // MARK: - HTML Assembly

    /// Build a complete HTML page from rendered markdown body.
    static func buildHTML(bodyHTML: String) -> String {
        var conditionalScripts = ""
        if needsMermaid(bodyHTML) { conditionalScripts += mermaidScript() }
        if needsMath(bodyHTML) { conditionalScripts += katexHead() }
        return baseHead() + bodyHTML + "</div>\n" + conditionalScripts + "</body>\n</html>"
    }

    // MARK: - Utilities

    static func jsonEncode(_ string: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [string])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }

    static func readFileWithFallback(url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return "# Unable to read file\n\nCould not read file data."
        }
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .shiftJIS, .utf16, .ascii]
        for encoding in encodings {
            if let content = String(data: data, encoding: encoding) {
                return content
            }
        }
        return "# Unable to read file\n\nThis file could not be decoded as text."
    }
}
