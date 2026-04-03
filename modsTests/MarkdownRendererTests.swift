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

    // MARK: - renderFrontmatterHTML

    func testRenderFrontmatterHTML() {
        let yaml = "title: Test\nauthor: Me"
        let html = MarkdownRenderer.renderFrontmatterHTML(yaml)
        XCTAssertTrue(html.contains("mods-frontmatter"))
        XCTAssertTrue(html.contains("mods-badge"))
        XCTAssertTrue(html.contains("title"))
        XCTAssertTrue(html.contains("Test"))
    }
}
