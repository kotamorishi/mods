import Cocoa
import QuickLookUI
import JavaScriptCore

class PreviewViewController: NSViewController, QLPreviewingController {
    var scrollView: NSScrollView!
    var textView: NSTextView!

    override func loadView() {
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        textView.backgroundColor = NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1.0)
        scrollView.documentView = textView
        scrollView.backgroundColor = NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1.0)
        self.view = scrollView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let bodyHTML = renderMarkdownToHTML(markdown)
            let fullHTML = wrapInDocument(bodyHTML)

            if let data = fullHTML.data(using: .utf8),
               let attrString = NSAttributedString(html: data, documentAttributes: nil) {
                textView.textStorage?.setAttributedString(attrString)
            } else {
                textView.string = markdown
            }
            handler(nil)
        } catch {
            handler(error)
        }
    }

    private func renderMarkdownToHTML(_ markdown: String) -> String {
        guard let ctx = JSContext() else { return "<pre>\(escapeHTML(markdown))</pre>" }

        let markedJS = Self.loadResource("marked.min", type: "js")
        if markedJS.isEmpty { return "<pre>\(escapeHTML(markdown))</pre>" }

        ctx.evaluateScript("var document = {}; var window = { document: document }; var self = {};")
        ctx.evaluateScript(markedJS)
        ctx.evaluateScript("""
            function renderMarkdown(md) {
                try {
                    marked.setOptions({ gfm: true, breaks: false });
                    return marked.parse(md);
                } catch(e) {
                    return '<pre>' + md + '</pre>';
                }
            }
        """)

        if let result = ctx.objectForKeyedSubscript("renderMarkdown")?.call(withArguments: [markdown])?.toString() {
            return result
        }
        return "<pre>\(escapeHTML(markdown))</pre>"
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func wrapInDocument(_ bodyHTML: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif;
            font-size: 13px; line-height: 1.6;
            color: #1f2328; background-color: #f0f0f0;
        }
        pre, code {
            font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace;
            font-size: 12px;
        }
        pre {
            padding: 12px;
            background-color: rgba(128,128,128,0.1);
            border-radius: 6px;
            overflow: auto;
        }
        :not(pre) > code {
            padding: 0.2em 0.4em;
            background-color: rgba(128,128,128,0.15);
            border-radius: 3px;
        }
        blockquote {
            margin: 0; padding: 0 1em;
            opacity: 0.7;
            border-left: 0.25em solid rgba(128,128,128,0.4);
        }
        table { border-collapse: collapse; }
        table th, table td { padding: 6px 13px; border: 1px solid rgba(128,128,128,0.3); }
        hr { border: none; border-top: 1px solid rgba(128,128,128,0.3); }
        a { color: #0969da; }
        img { max-width: 100%; }
        </style>
        </head>
        <body>\(bodyHTML)</body>
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
