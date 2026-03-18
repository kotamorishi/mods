import Foundation
import CMarkGFM

struct MarkdownRenderer {
    /// Convert a Markdown string to HTML using cmark-gfm with all GFM extensions.
    static func renderToHTML(_ markdown: String) -> String {
        // Initialize core extensions (tables, strikethrough, autolinks, tagfilter, tasklist)
        cmark_gfm_core_extensions_ensure_registered()

        let options = CMARK_OPT_DEFAULT
            | CMARK_OPT_UNSAFE     // Allow raw HTML passthrough
            | CMARK_OPT_FOOTNOTES  // Enable footnotes

        let parser = cmark_parser_new(Int32(options))
        defer { cmark_parser_free(parser) }

        // Attach all GFM extensions
        let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
        var extensions: UnsafeMutablePointer<cmark_llist>? = nil

        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
                extensions = cmark_llist_append(cmark_get_default_mem_allocator(), extensions, ext)
            }
        }

        // Parse
        let bytes = markdown.utf8
        cmark_parser_feed(parser, markdown, bytes.count)
        guard let doc = cmark_parser_finish(parser) else {
            cmark_llist_free(cmark_get_default_mem_allocator(), extensions)
            return "<p>Failed to parse markdown.</p>"
        }
        defer { cmark_node_free(doc) }

        // Render to HTML
        guard let htmlCStr = cmark_render_html(doc, Int32(options), extensions) else {
            cmark_llist_free(cmark_get_default_mem_allocator(), extensions)
            return "<p>Failed to render HTML.</p>"
        }
        defer { free(htmlCStr) }
        cmark_llist_free(cmark_get_default_mem_allocator(), extensions)

        var html = String(cString: htmlCStr)

        // Post-process: GitHub-style alert blocks
        html = processAlerts(html)

        return html
    }

    /// Convert GitHub alert blockquotes to styled divs.
    /// Input:  <blockquote>\n<p>[!NOTE]\nContent here</p>\n</blockquote>
    /// Output: <div class="markdown-alert markdown-alert-note">...</div>
    private static func processAlerts(_ html: String) -> String {
        let alertTypes = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"]
        var result = html

        for type in alertTypes {
            let typeLower = type.lowercased()
            let typeTitle = type.prefix(1).uppercased() + type.dropFirst().lowercased()

            // Pattern: blockquote containing [!TYPE] at the start
            // cmark-gfm outputs: <blockquote>\n<p>[!TYPE]\n or <p>[!TYPE]<br>\n
            let patterns = [
                "<blockquote>\n<p>[!\(type)]<br>\n",
                "<blockquote>\n<p>[!\(type)]\n",
            ]

            for pattern in patterns {
                while let range = result.range(of: pattern) {
                    // Find the closing </blockquote>
                    let searchStart = range.upperBound
                    guard let closeRange = result.range(of: "</blockquote>", range: searchStart..<result.endIndex) else {
                        break
                    }

                    let content = String(result[searchStart..<closeRange.lowerBound])
                    let replacement = """
                    <div class="markdown-alert markdown-alert-\(typeLower)">
                    <p class="markdown-alert-title">\(typeTitle)</p>
                    <p>\(content.replacingOccurrences(of: "</p>\n", with: "</p>\n<p>"))
                    </div>
                    """

                    result.replaceSubrange(range.lowerBound..<closeRange.upperBound, with: replacement)
                }
            }
        }

        return result
    }
}
