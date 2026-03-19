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

    private static let alertDefs: [(regex: NSRegularExpression, cssClass: String, title: String)] = {
        ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"].map { type in
            let regex = try! NSRegularExpression(
                pattern: "<blockquote>\\n<p>\\[!\(type)\\](?:<br>)?\\n([\\s\\S]*?)</blockquote>"
            )
            let cssClass = type.lowercased()
            let title = type.prefix(1).uppercased() + type.dropFirst().lowercased()
            return (regex, cssClass, title)
        }
    }()

    private static func processAlerts(_ html: String) -> String {
        guard html.contains("<blockquote>") && html.contains("[!") else { return html }
        var result = html

        for def in alertDefs {
            var nsResult = result as NSString
            var match = def.regex.firstMatch(in: result, range: NSRange(location: 0, length: nsResult.length))
            while let m = match {
                let content = nsResult.substring(with: m.range(at: 1))
                let replacement = """
                <div class="markdown-alert markdown-alert-\(def.cssClass)">
                <p class="markdown-alert-title">\(def.title)</p>
                \(content)</div>
                """
                nsResult = nsResult.replacingCharacters(in: m.range, with: replacement) as NSString
                result = nsResult as String
                match = def.regex.firstMatch(in: result, range: NSRange(location: 0, length: nsResult.length))
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

    // Match :shortcode: but not inside HTML tags or <code> blocks
    private static let emojiRegex = try! NSRegularExpression(
        pattern: ":([a-z0-9_+\\-]+):",
        options: []
    )

    /// Quick check for :shortcode: pattern — cheaper than loading the full emoji map
    private static let emojiQuickCheck = try! NSRegularExpression(
        pattern: ":[a-z0-9_+-]{1,50}:",
        options: []
    )

    private static func processEmoji(_ html: String) -> String {
        // Fast pre-check: skip emoji map loading if no :shortcode: pattern exists
        let range = NSRange(html.startIndex..., in: html)
        guard emojiQuickCheck.firstMatch(in: html, range: range) != nil else { return html }
        let map = loadEmojiMap()
        if map.isEmpty { return html }

        // Strip out <code>...</code> and HTML tags to find safe replacement zones
        // Strategy: replace emoji only in text nodes (outside tags and code elements)
        let nsHtml = html as NSString
        let fullRange = NSRange(location: 0, length: nsHtml.length)

        // Find all <code>...</code> ranges to exclude
        let codeBlockRegex = try! NSRegularExpression(pattern: "<code[^>]*>[\\s\\S]*?</code>", options: [])
        let codeRanges = codeBlockRegex.matches(in: html, range: fullRange).map { $0.range }

        // Find all HTML tag ranges to exclude
        let tagRegex = try! NSRegularExpression(pattern: "<[^>]+>", options: [])
        let tagRanges = tagRegex.matches(in: html, range: fullRange).map { $0.range }

        let excludedRanges = codeRanges + tagRanges

        var result = html
        // Process matches in reverse to preserve indices
        let matches = emojiRegex.matches(in: html, range: fullRange).reversed()
        for match in matches {
            let matchRange = match.range
            // Skip if inside an excluded range
            let isExcluded = excludedRanges.contains { NSIntersectionRange($0, matchRange).length > 0 }
            if isExcluded { continue }

            let name = nsHtml.substring(with: match.range(at: 1))
            if let emoji = map[name] {
                let swiftRange = Range(matchRange, in: result)!
                result.replaceSubrange(swiftRange, with: emoji)
            }
        }

        return result
    }

    // MARK: - Color Chips

    private static func processColorChips(_ html: String) -> String {
        // Fast check: no inline code means no color chips possible
        guard html.contains("<code>") else { return html }
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
