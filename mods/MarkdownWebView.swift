import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let zoomLevel: Double

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        loadHTML(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = zoomLevel
    }

    private func loadHTML(in webView: WKWebView) {
        let markedJS = loadResource("marked.min", type: "js")
        let highlightJS = loadResource("highlight.min", type: "js")
        let githubCSS = loadResource("github.min", type: "css")
        let githubDarkCSS = loadResource("github-dark.min", type: "css")

        let escapedMarkdown = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(githubCSS)

        @media (prefers-color-scheme: dark) {
            \(githubDarkCSS)
        }

        :root {
            color-scheme: light dark;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            font-size: 16px;
            line-height: 1.6;
            padding: 24px;
            max-width: 900px;
            margin: 0 auto;
            color: #1f2328;
            background: transparent;
        }

        @media (prefers-color-scheme: dark) {
            body {
                color: #e6edf3;
            }
        }

        img {
            max-width: 100%;
        }

        pre {
            padding: 16px;
            overflow: auto;
            border-radius: 6px;
            background-color: #f6f8fa;
        }

        @media (prefers-color-scheme: dark) {
            pre {
                background-color: #161b22;
            }
        }

        code {
            font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace;
            font-size: 85%;
        }

        :not(pre) > code {
            padding: 0.2em 0.4em;
            border-radius: 3px;
            background-color: rgba(175, 184, 193, 0.2);
        }

        blockquote {
            margin: 0;
            padding: 0 1em;
            color: #656d76;
            border-left: 0.25em solid #d0d7de;
        }

        @media (prefers-color-scheme: dark) {
            blockquote {
                color: #8b949e;
                border-left-color: #3d444d;
            }
        }

        table {
            border-collapse: collapse;
            width: 100%;
        }

        table th, table td {
            padding: 6px 13px;
            border: 1px solid #d0d7de;
        }

        @media (prefers-color-scheme: dark) {
            table th, table td {
                border-color: #3d444d;
            }
        }

        table tr:nth-child(2n) {
            background-color: rgba(175, 184, 193, 0.1);
        }

        hr {
            border: none;
            border-top: 1px solid #d0d7de;
        }

        @media (prefers-color-scheme: dark) {
            hr {
                border-top-color: #3d444d;
            }
        }

        a {
            color: #0969da;
            text-decoration: none;
        }

        @media (prefers-color-scheme: dark) {
            a {
                color: #4493f8;
            }
        }
        </style>
        <script>\(markedJS)</script>
        <script>\(highlightJS)</script>
        </head>
        <body>
        <div id="content"></div>
        <script>
        marked.setOptions({
            highlight: function(code, lang) {
                if (lang && hljs.getLanguage(lang)) {
                    return hljs.highlight(code, { language: lang }).value;
                }
                return hljs.highlightAuto(code).value;
            },
            gfm: true,
            breaks: false
        });
        document.getElementById('content').innerHTML = marked.parse(`\(escapedMarkdown)`);
        </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    private func loadResource(_ name: String, type: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: type),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }
}
