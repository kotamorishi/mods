import Foundation
import CMarkGFM

struct MarkdownRenderer {

    /// Thread-safe one-time registration of cmark-gfm extensions.
    /// Uses static let dispatch_once pattern to guarantee single execution.
    private static let extensionsRegistered: Bool = {
        cmark_gfm_core_extensions_ensure_registered()
        return true
    }()

    // MARK: - Frontmatter

    /// Extract YAML frontmatter from the start of a markdown string.
    static func extractFrontmatter(_ markdown: String) -> (frontmatter: String?, body: String) {
        guard markdown.hasPrefix("---") else { return (nil, markdown) }
        let lines = markdown.components(separatedBy: "\n")
        guard lines.count >= 3 else { return (nil, markdown) }
        // Find closing ---
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                let fmLines = lines[1..<i]
                let fm = fmLines.joined(separator: "\n")
                let body = lines[(i+1)...].joined(separator: "\n")
                return (fm.isEmpty ? nil : fm, body)
            }
        }
        return (nil, markdown)
    }

    /// Parse simple YAML key-value pairs into an ordered list.
    static func parseFrontmatter(_ yaml: String) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        let lines = yaml.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // Skip blank lines and comments
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                i += 1
                continue
            }
            guard let colonRange = line.range(of: ":") else { i += 1; continue }
            let key = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let valueAfterColon = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            if !valueAfterColon.isEmpty {
                // Inline value: "key: value" or "key: [a, b, c]"
                var val = valueAfterColon
                // Clean inline arrays: [a, b, c] → a, b, c
                if val.hasPrefix("[") && val.hasSuffix("]") {
                    val = String(val.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                }
                result.append((key: key, value: val))
            } else {
                // Multi-line list: collect "- item" lines
                var items: [String] = []
                var j = i + 1
                while j < lines.count {
                    let next = lines[j]
                    let trimmed = next.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("- ") {
                        items.append(String(trimmed.dropFirst(2)))
                        j += 1
                    } else if trimmed.isEmpty {
                        j += 1
                    } else {
                        break
                    }
                }
                if !items.isEmpty {
                    result.append((key: key, value: items.joined(separator: ", ")))
                    i = j
                    continue
                } else {
                    result.append((key: key, value: ""))
                }
            }
            i += 1
        }
        return result
    }

    /// Render frontmatter as a styled HTML block.
    static func renderFrontmatterHTML(_ yaml: String) -> String {
        let pairs = parseFrontmatter(yaml)
        guard !pairs.isEmpty else { return "" }
        var rows = ""
        for pair in pairs {
            rows += "<tr><td class=\"mods-fm-key\">\(escapeHTML(pair.key))</td><td>\(escapeHTML(pair.value))</td></tr>"
        }
        return """
        <div class="mods-frontmatter">
        <div class="mods-frontmatter-header"><span class="mods-badge">mods</span> FRONTMATTER</div>
        <table class="mods-frontmatter-table">\(rows)</table>
        </div>
        """
    }

    /// Convert a Markdown string to HTML using cmark-gfm with all GFM extensions.
    static func renderToHTML(_ markdown: String) -> String {
        _ = extensionsRegistered

        let (frontmatter, body) = extractFrontmatter(markdown)

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

        let bytes = body.utf8
        cmark_parser_feed(parser, body, bytes.count)
        guard let doc = cmark_parser_finish(parser) else {
            cmark_llist_free(cmark_get_default_mem_allocator(), extensions)
            return "<pre>\(escapeHTML(body))</pre>"
        }
        defer { cmark_node_free(doc) }

        guard let htmlCStr = cmark_render_html(doc, Int32(options), extensions) else {
            cmark_llist_free(cmark_get_default_mem_allocator(), extensions)
            return "<pre>\(escapeHTML(body))</pre>"
        }
        defer { free(htmlCStr) }
        cmark_llist_free(cmark_get_default_mem_allocator(), extensions)

        var html = String(cString: htmlCStr)

        html = wrapTables(html)
        html = blockExternalImages(html)
        html = processAlerts(html)
        html = addHeadingIDs(html)
        html = processEmoji(html)
        html = processColorChips(html)
        html = highlightKeywords(html)

        if let fm = frontmatter {
            html = renderFrontmatterHTML(fm) + html
        }

        return html
    }

    // MARK: - Heading IDs

    private static let headingTagRegex = try! NSRegularExpression(
        pattern: "<(h[1-6])>(.*?)</\\1>",
        options: .dotMatchesLineSeparators
    )

    /// Add unique IDs to heading tags for TOC navigation.
    private static func addHeadingIDs(_ html: String) -> String {
        guard html.contains("<h") else { return html }
        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)
        let matches = headingTagRegex.matches(in: html, range: range)
        guard !matches.isEmpty else { return html }

        var counts: [String: Int] = [:]
        var result = ""
        result.reserveCapacity(html.count + matches.count * 30)
        var cursor = html.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            result.append(contentsOf: html[cursor..<matchRange.lowerBound])
            let tag = nsHtml.substring(with: match.range(at: 1))
            let content = nsHtml.substring(with: match.range(at: 2))
            let text = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            var slug = text.lowercased()
                .replacingOccurrences(of: "[^a-z0-9\\s-]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            if slug.isEmpty { slug = "heading" }
            let count = counts[slug, default: 0]
            counts[slug] = count + 1
            let id = count == 0 ? slug : "\(slug)-\(count)"
            result.append("<\(tag) id=\"\(id)\">\(content)</\(tag)>")
            cursor = matchRange.upperBound
        }
        result.append(contentsOf: html[cursor...])
        return result
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
        let matches = externalImgRegex.matches(in: html, range: range)
        guard !matches.isEmpty else { return html }

        var result = ""
        result.reserveCapacity(html.count + matches.count * 200)
        var cursor = html.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: html) else { continue }
            result.append(contentsOf: html[cursor..<matchRange.lowerBound])
            let preAttrs = nsHtml.substring(with: match.range(at: 1))
            let url = nsHtml.substring(with: match.range(at: 3))
            let postAttrs = nsHtml.substring(with: match.range(at: 4))

            let combined = preAttrs + postAttrs
            let altMatch = altTextRegex.firstMatch(in: combined, range: NSRange(location: 0, length: combined.utf16.count))
            let altText = altMatch.map { (combined as NSString).substring(with: $0.range(at: 1)) } ?? "External image"

            result.append("""
            <div class="blocked-image" data-img-src="\(escapeHTML(url))" data-img-pre="\(escapeHTML(preAttrs))" data-img-post="\(escapeHTML(postAttrs))">
            <span class="blocked-image-icon">🖼</span>
            <span class="blocked-image-label">\(escapeHTML(altText))</span>
            <span class="blocked-image-url">\(escapeHTML(url))</span>
            <span class="blocked-image-action">Click to load</span>
            </div>
            """)
            cursor = matchRange.upperBound
        }
        result.append(contentsOf: html[cursor...])
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

        // Collect all alert matches across all types, sorted by position
        let nsHtml = html as NSString
        let fullRange = NSRange(location: 0, length: nsHtml.length)
        var allMatches: [(match: NSTextCheckingResult, def: (regex: NSRegularExpression, cssClass: String, title: String))] = []

        for def in alertDefs {
            for m in def.regex.matches(in: html, range: fullRange) {
                allMatches.append((m, def))
            }
        }
        guard !allMatches.isEmpty else { return html }
        allMatches.sort { $0.match.range.location < $1.match.range.location }

        var result = ""
        result.reserveCapacity(html.count + allMatches.count * 100)
        var cursor = html.startIndex

        for (m, def) in allMatches {
            guard let matchRange = Range(m.range, in: html) else { continue }
            // Skip overlapping matches
            if matchRange.lowerBound < cursor { continue }
            result.append(contentsOf: html[cursor..<matchRange.lowerBound])
            let content = nsHtml.substring(with: m.range(at: 1))
            result.append("""
            <div class="markdown-alert markdown-alert-\(def.cssClass)">
            <p class="markdown-alert-title">\(def.title)</p>
            \(content)</div>
            """)
            cursor = matchRange.upperBound
        }
        result.append(contentsOf: html[cursor...])
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

    /// Build sorted array of excluded range start positions for binary search.
    private static func buildExcludedRanges(html: String, fullRange: NSRange) -> [NSRange] {
        var ranges = codeBlockExcludeRegex.matches(in: html, range: fullRange).map { $0.range }
        ranges.append(contentsOf: htmlTagExcludeRegex.matches(in: html, range: fullRange).map { $0.range })
        ranges.sort { $0.location < $1.location }
        return ranges
    }

    /// O(log n) check if a position falls inside any excluded range using binary search.
    private static func isExcluded(location: Int, in ranges: [NSRange]) -> Bool {
        var lo = 0, hi = ranges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = ranges[mid]
            if location < r.location {
                hi = mid - 1
            } else if location >= r.location + r.length {
                lo = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    private static func processEmoji(_ html: String) -> String {
        let range = NSRange(html.startIndex..., in: html)
        guard emojiQuickCheck.firstMatch(in: html, range: range) != nil else { return html }
        let map = emojiMap
        if map.isEmpty { return html }

        let nsHtml = html as NSString
        let fullRange = NSRange(location: 0, length: nsHtml.length)
        let excluded = buildExcludedRanges(html: html, fullRange: fullRange)

        let matches = emojiRegex.matches(in: html, range: fullRange)
        guard !matches.isEmpty else { return html }

        var result = ""
        result.reserveCapacity(html.count)
        var cursor = html.startIndex

        for match in matches {
            if isExcluded(location: match.range.location, in: excluded) { continue }
            let name = nsHtml.substring(with: match.range(at: 1))
            guard let emoji = map[name], let swiftRange = Range(match.range, in: html) else { continue }
            result.append(contentsOf: html[cursor..<swiftRange.lowerBound])
            result.append(emoji)
            cursor = swiftRange.upperBound
        }
        result.append(contentsOf: html[cursor...])
        return result
    }

    // MARK: - Keyword Highlight

    private static func highlightKeywords(_ html: String) -> String {
        let keywords = HighlightKeywords.keywords()
        guard !keywords.isEmpty else { return html }

        let nsHtml = html as NSString
        let fullRange = NSRange(location: 0, length: nsHtml.length)
        let excluded = buildExcludedRanges(html: html, fullRange: fullRange)

        let escapedKeywords = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "(" + escapedKeywords.joined(separator: "|") + ")"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return html }

        let matches = regex.matches(in: html, range: fullRange)
        guard !matches.isEmpty else { return html }

        var result = ""
        result.reserveCapacity(html.count + matches.count * 40)
        var cursor = html.startIndex

        for match in matches {
            if isExcluded(location: match.range.location, in: excluded) { continue }
            guard let swiftRange = Range(match.range, in: html) else { continue }
            result.append(contentsOf: html[cursor..<swiftRange.lowerBound])
            let matched = nsHtml.substring(with: match.range)
            result.append("<span class=\"__mods-keyword-hl\">\(matched)</span>")
            cursor = swiftRange.upperBound
        }
        result.append(contentsOf: html[cursor...])
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

    // MARK: - Line Diff

    struct DiffHunk {
        var removedLines: [String]
        var addedLines: [String]
        var removedHTML: String = ""  // rendered HTML for removed lines
        var addedHTML: String = ""    // rendered HTML for added lines
        var blockIndex: Int = 0      // index of the top-level block (nth child of #content)
        var subIndex: Int = -1       // index of child within block (e.g., nth <li> in <ul>), -1 = before entire block
    }

    /// Render a set of markdown lines into plain text (strip markdown formatting).
    static func renderLinesToText(_ lines: [String]) -> [String] {
        lines.map { line in
            let html = renderToHTML(line)
            // Strip HTML tags to get plain text
            let text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? line : text
        }
    }

    /// Compute sequential line-level diff hunks between old and new text.
    static func lineDiff(old: String, new: String) -> [DiffHunk] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        // Simple LCS-based diff
        let n = oldLines.count, m = newLines.count
        // Build LCS table
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...max(n, 1) {
            guard i <= n else { break }
            for j in 1...max(m, 1) {
                guard j <= m else { break }
                if oldLines[i - 1] == newLines[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to get edit script with line numbers in new text
        struct Edit {
            enum Kind { case keep, remove, add }
            let kind: Kind
            let line: String
            let newLineNum: Int // line number in new text (-1 for removed)
        }
        var edits: [Edit] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                edits.append(Edit(kind: .keep, line: oldLines[i - 1], newLineNum: j - 1))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                edits.append(Edit(kind: .add, line: newLines[j - 1], newLineNum: j - 1))
                j -= 1
            } else {
                edits.append(Edit(kind: .remove, line: oldLines[i - 1], newLineNum: -1))
                i -= 1
            }
        }
        edits.reverse()

        // Group consecutive changes into hunks
        var hunks: [DiffHunk] = []
        var idx = 0
        while idx < edits.count {
            switch edits[idx].kind {
            case .keep:
                idx += 1
            case .remove, .add:
                var removed: [String] = []
                var added: [String] = []
                var firstAddedLine = -1
                while idx < edits.count {
                    switch edits[idx].kind {
                    case .remove: removed.append(edits[idx].line); idx += 1
                    case .add:
                        if firstAddedLine < 0 { firstAddedLine = edits[idx].newLineNum }
                        added.append(edits[idx].line); idx += 1
                    case .keep: break
                    }
                    if idx < edits.count && edits[idx].kind == .keep { break }
                }
                hunks.append(DiffHunk(removedLines: removed, addedLines: added, blockIndex: 0))
                // Store raw line number temporarily, mapHunksToBlocks will convert to block index
                if !hunks.isEmpty {
                    hunks[hunks.count - 1].blockIndex = firstAddedLine >= 0 ? firstAddedLine : 0
                }
            }
        }
        return hunks
    }

    /// Map diff hunk line numbers to block indices using cmark AST.
    /// Each top-level AST node corresponds to one direct child of `#content` in the rendered HTML.
    static func mapHunksToBlocks(hunks: [DiffHunk], newMarkdown: String) -> [DiffHunk] {
        _ = extensionsRegistered
        let (frontmatter, body) = extractFrontmatter(newMarkdown)
        // Frontmatter lines offset: diff line numbers are in the original file,
        // but cmark parses only the body, so cmark lines are relative to body.
        let fmLineCount = frontmatter != nil
            ? newMarkdown.components(separatedBy: "\n").count - body.components(separatedBy: "\n").count
            : 0

        let parser = cmark_parser_new(Int32(CMARK_OPT_DEFAULT | CMARK_OPT_FOOTNOTES))
        defer { cmark_parser_free(parser) }
        let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        cmark_parser_feed(parser, body, body.utf8.count)
        guard let doc = cmark_parser_finish(parser) else { return hunks }
        defer { cmark_node_free(doc) }

        // Walk top-level children, collect (index, startLine, endLine, children line ranges)
        struct ASTBlock {
            let index: Int
            let startLine: Int
            let endLine: Int
            let children: [(startLine: Int, endLine: Int)] // for lists/tables: child line ranges
        }
        var blocks: [ASTBlock] = []
        var node = cmark_node_first_child(doc)
        var idx = 0
        while let n = node {
            let start = Int(cmark_node_get_start_line(n)) - 1 + fmLineCount
            let end = Int(cmark_node_get_end_line(n)) - 1 + fmLineCount
            // Collect children for lists and tables
            var childRanges: [(startLine: Int, endLine: Int)] = []
            let nodeType = cmark_node_get_type(n)
            let isContainerNode = cmark_node_first_child(n) != nil && (nodeType == CMARK_NODE_LIST || String(cString: cmark_node_get_type_string(n)) == "table")
            if isContainerNode {
                var child = cmark_node_first_child(n)
                while let c = child {
                    let cs = Int(cmark_node_get_start_line(c)) - 1 + fmLineCount
                    let ce = Int(cmark_node_get_end_line(c)) - 1 + fmLineCount
                    childRanges.append((cs, ce))
                    child = cmark_node_next(c)
                }
            }
            blocks.append(ASTBlock(index: idx, startLine: start, endLine: end, children: childRanges))
            node = cmark_node_next(n)
            idx += 1
        }

        return hunks.map { hunk in
            var h = hunk
            let targetLine = h.blockIndex // raw 0-based line number from lineDiff
            // Render lines to plain text (strip markdown)
            h.removedHTML = renderLinesToText(h.removedLines).joined(separator: "\n")
            h.addedHTML = renderLinesToText(h.addedLines).joined(separator: "\n")
            for block in blocks {
                if targetLine >= block.startLine && targetLine <= block.endLine {
                    h.blockIndex = block.index
                    if !block.children.isEmpty {
                        for (ci, child) in block.children.enumerated() {
                            if targetLine >= child.startLine && targetLine <= child.endLine {
                                h.subIndex = ci
                                break
                            }
                        }
                    }
                    return h
                }
            }
            h.blockIndex = max(0, blocks.count - 1)
            return h
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}

/// Manages user-defined highlight keywords stored in shared UserDefaults (App Group).
enum HighlightKeywords {
    private static let key = "highlightKeywords"
    private static let suiteName = "group.com.kotamorishita.mods"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func keywords() -> [String] {
        // Migrate from old UserDefaults.standard to shared suite (one-time)
        if defaults.string(forKey: key) == nil,
           let oldData = UserDefaults.standard.string(forKey: key) {
            defaults.set(oldData, forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        guard let data = defaults.string(forKey: key)?.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return array
    }

    static func save(_ keywords: [String]) {
        if let data = try? JSONEncoder().encode(keywords),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: key)
        }
    }
}
