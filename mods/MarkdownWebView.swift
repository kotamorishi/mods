import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double

    // MARK: - Shared WKWebViewConfiguration (created once)

    nonisolated(unsafe) private static var sharedConfig: WKWebViewConfiguration?

    private static func configuration() -> WKWebViewConfiguration {
        if let config = sharedConfig { return config }
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // Inject highlight.js once — never re-parsed on subsequent loads
        let highlightJS = cachedResource("highlight.min", type: "js")
        if !highlightJS.isEmpty {
            let script = WKUserScript(source: highlightJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            controller.addUserScript(script)
        }

        // Inject the post-processing function once
        let postProcess = WKUserScript(source: Self.postProcessFunction, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        controller.addUserScript(postProcess)

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
        var isInitialLoadDone = false

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

        // First load: full HTML page with CSS shell + content
        let html = buildShellHTML()
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.isInitialLoadDone = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoomLevel

        if context.coordinator.currentMarkdown != markdown {
            context.coordinator.currentMarkdown = markdown

            if context.coordinator.isInitialLoadDone {
                // Fast path: swap content via JS instead of reloading the page
                updateContentViaJS(webView: webView)
            } else {
                let html = buildShellHTML()
                webView.loadHTMLString(html, baseURL: nil)
                context.coordinator.isInitialLoadDone = true
            }
        }
    }

    // MARK: - HTML Builder

    /// Post-processing function injected once via WKUserScript.
    /// Called after each content update to apply highlighting, mermaid, katex, etc.
    private static let postProcessFunction = """
    window.__modsPostProcess = function() {
        // Mermaid
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
        // Syntax highlighting
        document.querySelectorAll('pre code').forEach(function(block) {
            if (!block.classList.contains('language-math')) { hljs.highlightElement(block); }
        });
        // Checkboxes
        document.querySelectorAll('input[type="checkbox"]').forEach(function(cb) { cb.disabled = true; });
        // Math
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
    // Run on initial load
    window.__modsPostProcess();
    """

    nonisolated(unsafe) private static var cachedShellHead: String?

    /// Shell page head: CSS only (no JS in HTML — all JS via WKUserScript or evaluateJavaScript)
    private static func shellHead() -> String {
        if let cached = cachedShellHead { return cached }
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
        cachedShellHead = head
        return head
    }

    /// Build the initial full HTML page.
    private func buildShellHTML() -> String {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)

        let needsMermaid = bodyHTML.contains("language-mermaid")
        let needsMath = bodyHTML.contains("language-math") || bodyHTML.contains("$$") || Self.containsInlineMath(bodyHTML)

        // Inject mermaid/katex as inline scripts only when needed
        var conditionalScripts = ""
        if needsMermaid {
            conditionalScripts += "<script>\(Self.cachedResource("mermaid.min", type: "js"))</script>\n"
        }
        if needsMath {
            conditionalScripts += "<style>\(Self.cachedResource("katex.min", type: "css"))</style>\n"
            conditionalScripts += "<script>\(Self.cachedResource("katex.min", type: "js"))</script>\n"
            conditionalScripts += "<script>\(Self.cachedResource("katex-auto-render.min", type: "js"))</script>\n"
        }

        return Self.shellHead() + bodyHTML + "</div>\n" + conditionalScripts + "</body>\n</html>"
    }

    /// Fast content update: swap #content innerHTML via JS and re-run post-processing.
    private func updateContentViaJS(webView: WKWebView) {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)

        let needsMermaid = bodyHTML.contains("language-mermaid")
        let needsMath = bodyHTML.contains("language-math") || bodyHTML.contains("$$") || Self.containsInlineMath(bodyHTML)

        // Safely encode HTML as a JSON string for JavaScript
        let jsonData = try! JSONSerialization.data(withJSONObject: [bodyHTML])
        let jsonArray = String(data: jsonData, encoding: .utf8)!
        let jsonString = String(jsonArray.dropFirst().dropLast())

        var js = "document.getElementById('content').innerHTML = \(jsonString);\n"

        // Dynamically inject mermaid/katex if needed and not yet loaded
        if needsMermaid {
            js += """
            if (typeof mermaid === 'undefined') {
                var s = document.createElement('script');
                s.textContent = \(Self.jsonEncode(Self.cachedResource("mermaid.min", type: "js")));
                document.head.appendChild(s);
            }

            """
        }
        if needsMath {
            js += """
            if (typeof katex === 'undefined') {
                var ks = document.createElement('style');
                ks.textContent = \(Self.jsonEncode(Self.cachedResource("katex.min", type: "css")));
                document.head.appendChild(ks);
                var k1 = document.createElement('script');
                k1.textContent = \(Self.jsonEncode(Self.cachedResource("katex.min", type: "js")));
                document.head.appendChild(k1);
                var k2 = document.createElement('script');
                k2.textContent = \(Self.jsonEncode(Self.cachedResource("katex-auto-render.min", type: "js")));
                document.head.appendChild(k2);
            }

            """
        }

        js += "window.scrollTo(0, 0);\n"
        js += "window.__modsPostProcess();\n"

        webView.evaluateJavaScript(js)
    }

    // MARK: - Helpers

    private static let inlineMathRegex = try! NSRegularExpression(pattern: "\\$[^\\s$].*?[^\\s$]\\$|\\$[^\\s$]\\$", options: [])

    private static func containsInlineMath(_ html: String) -> Bool {
        let range = NSRange(html.startIndex..., in: html)
        return inlineMathRegex.firstMatch(in: html, range: range) != nil
    }

    private static func jsonEncode(_ string: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [string])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
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
