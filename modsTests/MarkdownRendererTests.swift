import XCTest
@testable import Mods

final class MarkdownRendererTests: XCTestCase {

    // MARK: - extractFrontmatter

    func testExtractFrontmatterWithValidYAML() {
        let md = "---\ntitle: Test\nauthor: Me\n---\n\n# Hello"
        let (fm, body) = MarkdownRenderer.extractFrontmatter(md)
        XCTAssertEqual(fm, "title: Test\nauthor: Me")
        XCTAssertEqual(body, "\n# Hello")
    }

    func testExtractFrontmatterWithoutFrontmatter() {
        let md = "# Hello\n\nSome text"
        let (fm, body) = MarkdownRenderer.extractFrontmatter(md)
        XCTAssertNil(fm)
        XCTAssertEqual(body, md)
    }

    func testExtractFrontmatterUnclosed() {
        let md = "---\ntitle: Test\n# Hello"
        let (fm, body) = MarkdownRenderer.extractFrontmatter(md)
        XCTAssertNil(fm)
        XCTAssertEqual(body, md)
    }

    func testExtractFrontmatterEmpty() {
        let md = "---\n---\n\n# Hello"
        let (fm, body) = MarkdownRenderer.extractFrontmatter(md)
        XCTAssertNil(fm) // empty frontmatter returns nil
        XCTAssertEqual(body, "\n# Hello")
    }

    // MARK: - parseFrontmatter

    func testParseFrontmatterKeyValue() {
        let yaml = "title: My Doc\nauthor: Me"
        let pairs = MarkdownRenderer.parseFrontmatter(yaml)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].key, "title")
        XCTAssertEqual(pairs[0].value, "My Doc")
        XCTAssertEqual(pairs[1].key, "author")
        XCTAssertEqual(pairs[1].value, "Me")
    }

    func testParseFrontmatterInlineArray() {
        let yaml = "tags: [a, b, c]"
        let pairs = MarkdownRenderer.parseFrontmatter(yaml)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].value, "a, b, c")
    }

    func testParseFrontmatterMultilineArray() {
        let yaml = "tags:\n- alpha\n- beta\n- gamma"
        let pairs = MarkdownRenderer.parseFrontmatter(yaml)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].key, "tags")
        XCTAssertEqual(pairs[0].value, "alpha, beta, gamma")
    }

    func testParseFrontmatterSkipsComments() {
        let yaml = "# comment\ntitle: Doc"
        let pairs = MarkdownRenderer.parseFrontmatter(yaml)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].key, "title")
    }

    func testParseFrontmatterSkipsBlankLines() {
        let yaml = "title: Doc\n\nauthor: Me"
        let pairs = MarkdownRenderer.parseFrontmatter(yaml)
        XCTAssertEqual(pairs.count, 2)
    }

    // MARK: - lineDiff

    func testLineDiffIdentical() {
        let text = "line1\nline2\nline3"
        let hunks = MarkdownRenderer.lineDiff(old: text, new: text)
        XCTAssertTrue(hunks.isEmpty)
    }

    func testLineDiffSingleLineChange() {
        let old = "line1\nline2\nline3"
        let new = "line1\nchanged\nline3"
        let hunks = MarkdownRenderer.lineDiff(old: old, new: new)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].removedLines, ["line2"])
        XCTAssertEqual(hunks[0].addedLines, ["changed"])
    }

    func testLineDiffLineAdded() {
        let old = "line1\nline2"
        let new = "line1\nline2\nline3"
        let hunks = MarkdownRenderer.lineDiff(old: old, new: new)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].addedLines, ["line3"])
        XCTAssertTrue(hunks[0].removedLines.isEmpty)
    }

    func testLineDiffLineRemoved() {
        let old = "line1\nline2\nline3"
        let new = "line1\nline3"
        let hunks = MarkdownRenderer.lineDiff(old: old, new: new)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].removedLines, ["line2"])
        XCTAssertTrue(hunks[0].addedLines.isEmpty)
    }

    func testLineDiffMultipleChanges() {
        let old = "a\nb\nc\nd\ne"
        let new = "a\nB\nc\nD\ne"
        let hunks = MarkdownRenderer.lineDiff(old: old, new: new)
        XCTAssertEqual(hunks.count, 2)
    }

    func testLineDiffEmptyStrings() {
        let hunks = MarkdownRenderer.lineDiff(old: "", new: "")
        XCTAssertTrue(hunks.isEmpty)
    }

    // MARK: - renderLinesToText

    func testRenderLinesToTextTableRow() {
        let result = MarkdownRenderer.renderLinesToText(["| L2 | C2 | R2 |"])
        XCTAssertEqual(result, ["L2 | C2 | R2"])
    }

    func testRenderLinesToTextTableSeparator() {
        let result = MarkdownRenderer.renderLinesToText(["|:-----|:------:|------:|"])
        XCTAssertEqual(result, [""])
    }

    func testRenderLinesToTextListItem() {
        let result = MarkdownRenderer.renderLinesToText(["- item text"])
        XCTAssertEqual(result, ["item text"])
    }

    func testRenderLinesToTextHeading() {
        let result = MarkdownRenderer.renderLinesToText(["## My Heading"])
        XCTAssertEqual(result, ["My Heading"])
    }

    func testRenderLinesToTextBold() {
        let result = MarkdownRenderer.renderLinesToText(["**bold** text"])
        XCTAssertEqual(result, ["bold text"])
    }

    func testRenderLinesToTextTaskList() {
        let result = MarkdownRenderer.renderLinesToText(["- [x] Completed"])
        XCTAssertEqual(result, ["Completed"])
    }

    func testRenderLinesToTextInlineCode() {
        let result = MarkdownRenderer.renderLinesToText(["`code` here"])
        XCTAssertEqual(result, ["code here"])
    }

    // MARK: - renderFrontmatterHTML

    func testRenderFrontmatterHTML() {
        let yaml = "title: Test\nauthor: Me"
        let html = MarkdownRenderer.renderFrontmatterHTML(yaml)
        XCTAssertTrue(html.contains("mods-frontmatter"))
        XCTAssertTrue(html.contains("mods-badge"))
        XCTAssertTrue(html.contains("title"))
        XCTAssertTrue(html.contains("Test"))
    }

    // MARK: - renderHunkText

    func testRenderHunkTextStripsMarkdown() {
        let hunk = MarkdownRenderer.DiffHunk(removedLines: ["## Old heading"], addedLines: ["## New heading"])
        let rendered = MarkdownRenderer.renderHunkText(hunks: [hunk])
        XCTAssertEqual(rendered[0].removedHTML, "Old heading")
        XCTAssertEqual(rendered[0].addedHTML, "New heading")
    }

    func testRenderHunkTextStripsTablePipes() {
        let hunk = MarkdownRenderer.DiffHunk(removedLines: ["| A | B |"], addedLines: ["| C | D |"])
        let rendered = MarkdownRenderer.renderHunkText(hunks: [hunk])
        XCTAssertEqual(rendered[0].removedHTML, "A | B")
        XCTAssertEqual(rendered[0].addedHTML, "C | D")
    }

    func testRenderHunkTextStripsListMarkers() {
        let hunk = MarkdownRenderer.DiffHunk(removedLines: ["- old item"], addedLines: ["- new item"])
        let rendered = MarkdownRenderer.renderHunkText(hunks: [hunk])
        XCTAssertEqual(rendered[0].removedHTML, "old item")
        XCTAssertEqual(rendered[0].addedHTML, "new item")
    }
}
