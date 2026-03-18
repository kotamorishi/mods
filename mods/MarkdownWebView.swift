import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double

    nonisolated(unsafe) private static var cachedStyleBlock: String?

    private static func styleBlock() -> String {
        if let cached = cachedStyleBlock { return cached }
        let githubCSS = cachedResource("github.min", type: "css")
        let githubDarkCSS = cachedResource("github-dark.min", type: "css")
        let block = """
        <style>
        \(githubCSS)
        @media (prefers-color-scheme: dark) { \(githubDarkCSS) }
        :root { color-scheme: light dark; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.5;
            word-wrap: break-word;
            padding: 32px;
            max-width: 900px;
            margin: 0 auto;
            color: #1f2328;
            background-color: #ffffff;
        }
        @media (prefers-color-scheme: dark) {
            body { color: #e6edf3; background-color: #0d1117; }
        }

        h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
        h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
        h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: 0.875em; }
        h6 { font-size: 0.85em; color: #656d76; }
        @media (prefers-color-scheme: dark) { h1, h2 { border-bottom-color: #3d444d; } h6 { color: #8b949e; } }

        p { margin-top: 0; margin-bottom: 16px; }
        a { color: #0969da; text-decoration: none; }
        a:hover { text-decoration: underline; }
        @media (prefers-color-scheme: dark) { a { color: #4493f8; } }
        img { max-width: 100%; box-sizing: border-box; }

        code, tt { font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; font-size: 85%; }
        :not(pre) > code { padding: 0.2em 0.4em; margin: 0; border-radius: 6px; background-color: rgba(175, 184, 193, 0.2); }
        pre { padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45; border-radius: 6px; background-color: #f6f8fa; margin-bottom: 16px; }
        pre code { padding: 0; margin: 0; background-color: transparent; border: 0; font-size: 100%; }
        @media (prefers-color-scheme: dark) { pre { background-color: #161b22; } }

        blockquote { margin: 0 0 16px 0; padding: 0 1em; color: #656d76; border-left: 0.25em solid #d0d7de; }
        @media (prefers-color-scheme: dark) { blockquote { color: #8b949e; border-left-color: #3d444d; } }

        ul, ol { margin-top: 0; margin-bottom: 16px; padding-left: 2em; }
        ul { list-style-type: disc; }
        ul ul { list-style-type: circle; }
        ul ul ul { list-style-type: square; }
        li { margin-top: 0.25em; }
        li > p { margin-top: 16px; margin-bottom: 16px; }
        li > p:first-child { margin-top: 0; }
        li > p:last-child { margin-bottom: 0; }
        ul.contains-task-list { list-style-type: none; padding-left: 1.6em; }
        ul.contains-task-list li input[type="checkbox"] { margin-right: 0.5em; }

        table { border-spacing: 0; border-collapse: collapse; width: max-content; max-width: 100%; overflow: auto; margin-bottom: 16px; display: block; }
        table th { font-weight: 600; padding: 6px 13px; border: 1px solid #d0d7de; }
        table td { padding: 6px 13px; border: 1px solid #d0d7de; }
        table tr { background-color: #ffffff; border-top: 1px solid #d1d9e0; }
        table tr:nth-child(2n) { background-color: #f6f8fa; }
        @media (prefers-color-scheme: dark) { table th, table td { border-color: #3d444d; } table tr { background-color: #0d1117; border-top-color: #3d444d; } table tr:nth-child(2n) { background-color: #161b22; } }

        hr { height: 0.25em; padding: 0; margin: 24px 0; background-color: #d0d7de; border: 0; }
        @media (prefers-color-scheme: dark) { hr { background-color: #3d444d; } }
        del { text-decoration: line-through; }

        .color-chip { display: inline-block; width: 0.9em; height: 0.9em; border-radius: 50%; margin-right: 0.3em; vertical-align: middle; border: 1px solid rgba(0,0,0,0.15); }

        .markdown-alert { padding: 8px 16px; margin-bottom: 16px; border-left: 0.25em solid; border-radius: 6px; }
        .markdown-alert-title { display: flex; align-items: center; font-weight: 600; margin-bottom: 4px; }
        .markdown-alert-note { border-left-color: #0969da; }
        .markdown-alert-note .markdown-alert-title { color: #0969da; }
        .markdown-alert-tip { border-left-color: #1a7f37; }
        .markdown-alert-tip .markdown-alert-title { color: #1a7f37; }
        .markdown-alert-important { border-left-color: #8250df; }
        .markdown-alert-important .markdown-alert-title { color: #8250df; }
        .markdown-alert-warning { border-left-color: #9a6700; }
        .markdown-alert-warning .markdown-alert-title { color: #9a6700; }
        .markdown-alert-caution { border-left-color: #cf222e; }
        .markdown-alert-caution .markdown-alert-title { color: #cf222e; }

        .footnotes { font-size: 85%; color: #656d76; border-top: 1px solid #d0d7de; margin-top: 24px; padding-top: 16px; }
        @media (prefers-color-scheme: dark) { .footnotes { color: #8b949e; border-top-color: #3d444d; } }
        sub, sup { font-size: 75%; line-height: 0; position: relative; vertical-align: baseline; }
        sup { top: -0.5em; }
        sub { bottom: -0.25em; }
        kbd { display: inline-block; padding: 3px 5px; font-size: 11px; line-height: 10px; color: #1f2328; vertical-align: middle; background-color: #f6f8fa; border: 1px solid #d0d7de; border-radius: 6px; box-shadow: inset 0 -1px 0 #d0d7de; }
        @media (prefers-color-scheme: dark) { kbd { color: #e6edf3; background-color: #161b22; border-color: #3d444d; box-shadow: inset 0 -1px 0 #3d444d; } }
        </style>
        """
        cachedStyleBlock = block
        return block
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.autoresizingMask = [.width, .height]
        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoomLevel
    }

    private func buildHTML() -> String {
        let bodyHTML = MarkdownRenderer.renderToHTML(markdown)

        // Detect which optional libraries are needed
        let needsMermaid = bodyHTML.contains("language-mermaid")
        let needsMath = bodyHTML.contains("$") || bodyHTML.contains("language-math")

        // Build script/css tags — only include heavy libs when needed
        var scriptTags = "<script>\(Self.cachedResource("highlight.min", type: "js"))</script>\n"
        if needsMermaid { scriptTags += "<script>\(Self.cachedResource("mermaid.min", type: "js"))</script>\n" }
        var cssTags = ""
        if needsMath {
            cssTags = "<style>\(Self.cachedResource("katex.min", type: "css"))</style>\n"
            scriptTags += "<script>\(Self.cachedResource("katex.min", type: "js"))</script>\n"
            scriptTags += "<script>\(Self.cachedResource("katex-auto-render.min", type: "js"))</script>\n"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(cssTags)\(Self.styleBlock())
        \(scriptTags)</head>
        <body>
        <div id="content">\(bodyHTML)</div>
        <script>
        // Mermaid diagrams
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
        document.querySelectorAll('input[type="checkbox"]').forEach(function(cb) { cb.disabled = true; });

        // Math rendering
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
        </body>
        </html>
        """
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
