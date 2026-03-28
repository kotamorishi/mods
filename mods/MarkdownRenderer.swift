import Foundation
import CMarkGFM

struct MarkdownRenderer {

    /// Thread-safe one-time registration of cmark-gfm extensions.
    /// Uses static let dispatch_once pattern to guarantee single execution.
    private static let extensionsRegistered: Bool = {
        cmark_gfm_core_extensions_ensure_registered()
        return true
    }()

    /// Convert a Markdown string to HTML using cmark-gfm with all GFM extensions.
    static func renderToHTML(_ markdown: String) -> String {
        _ = extensionsRegistered

        // Security: CMARK_OPT_DEFAULT escapes all raw HTML in markdown.
        // Do NOT use CMARK_OPT_UNSAFE — it passes raw HTML through,
        // enabling XSS via crafted markdown files.
        let options = CMARK_OPT_DEFAULT
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
            return "<pre>\(escapeHTML(markdown))</pre>"
        }
        defer { cmark_node_free(doc) }

        guard let htmlCStr = cmark_render_html(doc, Int32(options), extensions) else {
            cmark_llist_free(cmark_get_default_mem_allocator(), extensions)
            return "<pre>\(escapeHTML(markdown))</pre>"
        }
        defer { free(htmlCStr) }
        cmark_llist_free(cmark_get_default_mem_allocator(), extensions)

        var html = String(cString: htmlCStr)

        html = wrapTables(html)
        html = blockExternalImages(html)
        html = processAlerts(html)
        html = processEmoji(html)
        html = processColorChips(html)

        return html
    }

    // MARK: - Table Wrapping

    /// Wrap <table> elements in a scrollable container so tables that fit
    /// the viewport width are displayed normally (no scroll), while wide
    /// tables get horizontal scrolling.
    private static func wrapTables(_ html: String) -> String {
        guard html.contains("<table") else { return html }
        return html
            .replacingOccurrences(of: "<table", with: "<div class=\"table-wrapper\"><table")
            .replacingOccurrences(of: "</table>", with: "</table></div>")
    }

    // MARK: - External Image Blocking

    /// Replace external image src with data-src and add a placeholder.
    /// Users must click to load external images (prevents tracking pixels and IP leaks).
    private static let externalImgRegex = try! NSRegularExpression(
        pattern: "<img\\s+([^>]*?)src\\s*=\\s*([\"'])(https?://[^\"']+)\\2([^>]*?)>",
        options: .caseInsensitive
    )
    private static let altTextRegex = try! NSRegularExpression(
        pattern: "alt\\s*=\\s*[\"']([^\"']*)[\"']",
        options: .caseInsensitive
    )

    private static func blockExternalImages(_ html: String) -> String {
        guard html.contains("<img") else { return html }
        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)
        let matches = externalImgRegex.matches(in: html, range: range).reversed()

        var result = html
        for match in matches {
            let fullRange = match.range
            let preAttrs = nsHtml.substring(with: match.range(at: 1))
            let url = nsHtml.substring(with: match.range(at: 3))
            let postAttrs = nsHtml.substring(with: match.range(at: 4))

            let combined = preAttrs + postAttrs
            let altMatch = altTextRegex.firstMatch(in: combined, range: NSRange(location: 0, length: combined.utf16.count))
            let altText = altMatch.map { (combined as NSString).substring(with: $0.range(at: 1)) } ?? "External image"

            let placeholder = """
            <div class="blocked-image" data-img-src="\(escapeHTML(url))" data-img-pre="\(escapeHTML(preAttrs))" data-img-post="\(escapeHTML(postAttrs))">
            <span class="blocked-image-icon">🖼</span>
            <span class="blocked-image-label">\(escapeHTML(altText))</span>
            <span class="blocked-image-url">\(escapeHTML(url))</span>
            <span class="blocked-image-action">Click to load</span>
            </div>
            """

            guard let swiftRange = Range(fullRange, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: placeholder)
        }

        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Alerts

    private static let alertDefs: [(regex: NSRegularExpression, cssClass: String, title: String)] = {
        ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"].map { type in
            // Match alert blockquote without crossing into other blockquotes
            let regex = try! NSRegularExpression(
                pattern: "<blockquote>\\n<p>\\[!\(type)\\](?:<br>)?\\n((?:(?!<blockquote>)[\\s\\S])*?)</blockquote>"
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

    /// Emoji map loaded once via dispatch_once pattern.
    private static let emojiMap: [String: String] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json")
                ?? HTMLBuilder._parentAppBundle?.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }()

    // Match :shortcode: but not inside HTML tags or <code> blocks
    private static let emojiRegex = try! NSRegularExpression(
        pattern: ":([a-z0-9_+\\-]+):",
        options: []
    )
    private static let codeBlockExcludeRegex = try! NSRegularExpression(pattern: "<code[^>]*>[\\s\\S]*?</code>")
    private static let htmlTagExcludeRegex = try! NSRegularExpression(pattern: "<[^>]+>")

    /// Quick check for :shortcode: pattern — cheaper than loading the full emoji map
    private static let emojiQuickCheck = try! NSRegularExpression(
        pattern: ":[a-z0-9_+-]{1,50}:",
        options: []
    )

    private static func processEmoji(_ html: String) -> String {
        // Fast pre-check: skip emoji map loading if no :shortcode: pattern exists
        let range = NSRange(html.startIndex..., in: html)
        guard emojiQuickCheck.firstMatch(in: html, range: range) != nil else { return html }
        let map = emojiMap
        if map.isEmpty { return html }

        // Strip out <code>...</code> and HTML tags to find safe replacement zones
        // Strategy: replace emoji only in text nodes (outside tags and code elements)
        let nsHtml = html as NSString
        let fullRange = NSRange(location: 0, length: nsHtml.length)

        let codeRanges = codeBlockExcludeRegex.matches(in: html, range: fullRange).map { $0.range }
        let tagRanges = htmlTagExcludeRegex.matches(in: html, range: fullRange).map { $0.range }

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
            if let emoji = map[name], let swiftRange = Range(matchRange, in: result) {
                result.replaceSubrange(swiftRange, with: emoji)
            }
        }

        return result
    }

    // MARK: - Color Chips

    private static let colorChipRegexes: [NSRegularExpression] = [
        // Hex: #RGB, #RRGGBB, #RRGGBBAA — only hex chars allowed
        try! NSRegularExpression(pattern: "<code>(#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8}))</code>"),
        // rgb/rgba: only digits, commas, spaces, dots, % allowed inside parens
        try! NSRegularExpression(pattern: "<code>(rgba?\\([0-9,\\s.%]+\\))</code>"),
        // hsl/hsla: only digits, commas, spaces, dots, % allowed inside parens
        try! NSRegularExpression(pattern: "<code>(hsla?\\([0-9,\\s.%]+\\))</code>"),
    ]
    private static let colorChipTemplate = "<code><span class=\"color-chip\" style=\"background-color: $1;\"></span>$1</code>"

    private static func processColorChips(_ html: String) -> String {
        guard html.contains("<code>") else { return html }
        var result = html
        for regex in colorChipRegexes {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: colorChipTemplate
            )
        }
        return result
    }
}
