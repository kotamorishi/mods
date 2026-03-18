import Foundation
import CMarkGFM

struct MarkdownRenderer {
    nonisolated(unsafe) private static var emojiMap: [String: String]? = nil

    /// Convert a Markdown string to HTML using cmark-gfm with all GFM extensions.
    static func renderToHTML(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        let options = CMARK_OPT_DEFAULT
            | CMARK_OPT_UNSAFE
            | CMARK_OPT_FOOTNOTES

        let parser = cmark_parser_new(Int32(options))
        defer { cmark_parser_free(parser) }

        let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
        var extensions: UnsafeMutablePointer<cmark_llist>? = nil

        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
                extensions = cmark_llist_append(cmark_get_default_mem_allocator(), extensions, ext)
            }
        }

        let bytes = markdown.utf8
        cmark_parser_feed(parser, markdown, bytes.count)
        guard let doc = cmark_parser_finish(parser) else {
            cmark_llist_free(cmark_get_default_mem_allocator(), extensions)
            return "<p>Failed to parse markdown.</p>"
        }
        defer { cmark_node_free(doc) }

        guard let htmlCStr = cmark_render_html(doc, Int32(options), extensions) else {
            cmark_llist_free(cmark_get_default_mem_allocator(), extensions)
            return "<p>Failed to render HTML.</p>"
        }
        defer { free(htmlCStr) }
        cmark_llist_free(cmark_get_default_mem_allocator(), extensions)

        var html = String(cString: htmlCStr)

        html = processAlerts(html)
        html = processEmoji(html)
        html = processColorChips(html)

        return html
    }

    // MARK: - Alerts

    private static func processAlerts(_ html: String) -> String {
        let alertTypes = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"]
        var result = html

        for type in alertTypes {
            let typeLower = type.lowercased()
            let typeTitle = type.prefix(1).uppercased() + type.dropFirst().lowercased()

            let patterns = [
                "<blockquote>\n<p>[!\(type)]<br>\n",
                "<blockquote>\n<p>[!\(type)]\n",
            ]

            for pattern in patterns {
                while let range = result.range(of: pattern) {
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

    // MARK: - Emoji

    private static func loadEmojiMap() -> [String: String] {
        if let cached = emojiMap { return cached }
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        emojiMap = map
        return map
    }

    private static func processEmoji(_ html: String) -> String {
        let map = loadEmojiMap()
        if map.isEmpty { return html }

        var result = ""
        var inTag = false
        var inCode = false
        var i = html.startIndex

        while i < html.endIndex {
            let ch = html[i]

            if ch == "<" {
                inTag = true
                let tagStart = i
                // Check for <code> or </code>
                let rest = html[i...]
                if rest.hasPrefix("<code") { inCode = true }
                else if rest.hasPrefix("</code") { inCode = false }
                result.append(ch)
                i = html.index(after: i)
                continue
            }
            if ch == ">" {
                inTag = false
                result.append(ch)
                i = html.index(after: i)
                continue
            }

            // Only process emoji outside of HTML tags and code elements
            if !inTag && !inCode && ch == ":" {
                let afterColon = html.index(after: i)
                if afterColon < html.endIndex {
                    // Find closing colon
                    if let endColon = html[afterColon...].firstIndex(of: ":") {
                        let name = String(html[afterColon..<endColon])
                        if name.count > 0 && name.count < 50 && !name.contains(" ") && !name.contains("<"),
                           let emoji = map[name] {
                            result.append(emoji)
                            i = html.index(after: endColon)
                            continue
                        }
                    }
                }
            }

            result.append(ch)
            i = html.index(after: i)
        }

        return result
    }

    // MARK: - Color Chips

    private static func processColorChips(_ html: String) -> String {
        // Match <code>#hex</code>, <code>rgb(...)</code>, <code>hsl(...)</code>
        var result = html

        // Hex colors: #RGB, #RRGGBB, #RRGGBBAA
        let hexPattern = try! NSRegularExpression(
            pattern: "<code>(#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8}))</code>",
            options: []
        )
        result = hexPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "<code><span class=\"color-chip\" style=\"background-color: $1;\"></span>$1</code>"
        )

        // rgb/rgba colors
        let rgbPattern = try! NSRegularExpression(
            pattern: "<code>(rgba?\\([^)]+\\))</code>",
            options: []
        )
        result = rgbPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "<code><span class=\"color-chip\" style=\"background-color: $1;\"></span>$1</code>"
        )

        // hsl/hsla colors
        let hslPattern = try! NSRegularExpression(
            pattern: "<code>(hsla?\\([^)]+\\))</code>",
            options: []
        )
        result = hslPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "<code><span class=\"color-chip\" style=\"background-color: $1;\"></span>$1</code>"
        )

        return result
    }
}
