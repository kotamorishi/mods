import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double

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
        let markedJS = Self.loadResource("marked.min", type: "js")
        let highlightJS = Self.loadResource("highlight.min", type: "js")
        let githubCSS = Self.loadResource("github.min", type: "css")
        let githubDarkCSS = Self.loadResource("github-dark.min", type: "css")

        let jsonData = try! JSONSerialization.data(withJSONObject: [markdown])
        let jsonArray = String(data: jsonData, encoding: .utf8)!
        let jsonString = jsonArray.dropFirst().dropLast()

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
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

        /* Headings */
        h1, h2, h3, h4, h5, h6 {
            margin-top: 24px;
            margin-bottom: 16px;
            font-weight: 600;
            line-height: 1.25;
        }
        h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
        h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: 0.875em; }
        h6 { font-size: 0.85em; color: #656d76; }
        @media (prefers-color-scheme: dark) {
            h1, h2 { border-bottom-color: #3d444d; }
            h6 { color: #8b949e; }
        }

        /* Paragraphs */
        p { margin-top: 0; margin-bottom: 16px; }

        /* Links */
        a { color: #0969da; text-decoration: none; }
        a:hover { text-decoration: underline; }
        @media (prefers-color-scheme: dark) { a { color: #4493f8; } }

        /* Images */
        img { max-width: 100%; box-sizing: border-box; }

        /* Code */
        code, tt {
            font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
            font-size: 85%;
        }
        :not(pre) > code {
            padding: 0.2em 0.4em;
            margin: 0;
            border-radius: 6px;
            background-color: rgba(175, 184, 193, 0.2);
        }
        pre {
            padding: 16px;
            overflow: auto;
            font-size: 85%;
            line-height: 1.45;
            border-radius: 6px;
            background-color: #f6f8fa;
            margin-bottom: 16px;
        }
        pre code {
            padding: 0;
            margin: 0;
            background-color: transparent;
            border: 0;
            font-size: 100%;
        }
        @media (prefers-color-scheme: dark) {
            pre { background-color: #161b22; }
        }

        /* Blockquotes */
        blockquote {
            margin: 0 0 16px 0;
            padding: 0 1em;
            color: #656d76;
            border-left: 0.25em solid #d0d7de;
        }
        @media (prefers-color-scheme: dark) {
            blockquote { color: #8b949e; border-left-color: #3d444d; }
        }

        /* Lists */
        ul, ol {
            margin-top: 0;
            margin-bottom: 16px;
            padding-left: 2em;
        }
        li + li { margin-top: 0.25em; }

        /* Task lists */
        .contains-task-list { list-style-type: none; padding-left: 0; }
        .task-list-item { position: relative; padding-left: 1.5em; }
        .task-list-item input[type="checkbox"] {
            position: absolute;
            left: 0;
            top: 0.3em;
            margin: 0;
        }

        /* Tables */
        table {
            border-spacing: 0;
            border-collapse: collapse;
            width: max-content;
            max-width: 100%;
            overflow: auto;
            margin-bottom: 16px;
            display: block;
        }
        table th {
            font-weight: 600;
            padding: 6px 13px;
            border: 1px solid #d0d7de;
        }
        table td {
            padding: 6px 13px;
            border: 1px solid #d0d7de;
        }
        table tr { background-color: #ffffff; border-top: 1px solid #d1d9e0; }
        table tr:nth-child(2n) { background-color: #f6f8fa; }
        @media (prefers-color-scheme: dark) {
            table th, table td { border-color: #3d444d; }
            table tr { background-color: #0d1117; border-top-color: #3d444d; }
            table tr:nth-child(2n) { background-color: #161b22; }
        }

        /* Horizontal rule */
        hr {
            height: 0.25em;
            padding: 0;
            margin: 24px 0;
            background-color: #d0d7de;
            border: 0;
        }
        @media (prefers-color-scheme: dark) { hr { background-color: #3d444d; } }

        /* Strikethrough */
        del { text-decoration: line-through; }

        /* Alerts (GFM) */
        .markdown-alert {
            padding: 8px 16px;
            margin-bottom: 16px;
            border-left: 0.25em solid;
            border-radius: 6px;
        }
        .markdown-alert-title {
            display: flex;
            align-items: center;
            font-weight: 600;
            margin-bottom: 4px;
        }
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

        /* Footnotes */
        .footnotes { font-size: 85%; color: #656d76; border-top: 1px solid #d0d7de; margin-top: 24px; padding-top: 16px; }
        @media (prefers-color-scheme: dark) {
            .footnotes { color: #8b949e; border-top-color: #3d444d; }
        }

        /* Sub/sup */
        sub, sup { font-size: 75%; line-height: 0; position: relative; vertical-align: baseline; }
        sup { top: -0.5em; }
        sub { bottom: -0.25em; }

        /* Keyboard */
        kbd {
            display: inline-block;
            padding: 3px 5px;
            font-size: 11px;
            line-height: 10px;
            color: #1f2328;
            vertical-align: middle;
            background-color: #f6f8fa;
            border: 1px solid #d0d7de;
            border-radius: 6px;
            box-shadow: inset 0 -1px 0 #d0d7de;
        }
        @media (prefers-color-scheme: dark) {
            kbd { color: #e6edf3; background-color: #161b22; border-color: #3d444d; box-shadow: inset 0 -1px 0 #3d444d; }
        }
        </style>
        <script>\(markedJS)</script>
        <script>\(highlightJS)</script>
        </head>
        <body>
        <div id="content"></div>
        <script>
        try {
            var md = \(jsonString);

            // Custom renderer for GitHub-style alerts
            var renderer = new marked.Renderer();
            var origBlockquote = renderer.blockquote.bind(renderer);

            marked.setOptions({
                gfm: true,
                breaks: false,
                renderer: renderer
            });

            var html = marked.parse(md);

            // Post-process: convert GitHub alerts
            html = html.replace(/<blockquote>\\n<p>\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]<br>([\\s\\S]*?)<\\/p>\\n<\\/blockquote>/gi,
                function(match, type, content) {
                    var t = type.charAt(0).toUpperCase() + type.slice(1).toLowerCase();
                    return '<div class="markdown-alert markdown-alert-' + type.toLowerCase() + '">' +
                           '<p class="markdown-alert-title">' + t + '</p>' +
                           '<p>' + content + '</p></div>';
                }
            );
            html = html.replace(/<blockquote>\\n<p>\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]\\n([\\s\\S]*?)<\\/p>\\n<\\/blockquote>/gi,
                function(match, type, content) {
                    var t = type.charAt(0).toUpperCase() + type.slice(1).toLowerCase();
                    return '<div class="markdown-alert markdown-alert-' + type.toLowerCase() + '">' +
                           '<p class="markdown-alert-title">' + t + '</p>' +
                           '<p>' + content + '</p></div>';
                }
            );

            document.getElementById('content').innerHTML = html;

            // Syntax highlighting
            document.querySelectorAll('pre code').forEach(function(block) {
                hljs.highlightElement(block);
            });

            // Make checkboxes disabled
            document.querySelectorAll('input[type="checkbox"]').forEach(function(cb) {
                cb.disabled = true;
            });
        } catch(e) {
            document.body.innerText = 'Render error: ' + e.message;
        }
        </script>
        </body>
        </html>
        """
    }

    private static func loadResource(_ name: String, type: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: type),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }
}
