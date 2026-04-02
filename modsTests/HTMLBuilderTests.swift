import XCTest
@testable import Mods

final class HTMLBuilderTests: XCTestCase {

    // MARK: - readFileWithFallback

    func testReadExistingUTF8File() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test_utf8.md")
        let content = "# Hello\n\nWorld"
        try? content.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = HTMLBuilder.readFileWithFallback(url: tmp)
        XCTAssertEqual(result, content)
    }

    func testReadNonExistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/file.md")
        let result = HTMLBuilder.readFileWithFallback(url: url)
        XCTAssertTrue(result.contains("Unable to read file"))
    }

    func testReadEmptyFile() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test_empty.md")
        try? Data().write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = HTMLBuilder.readFileWithFallback(url: tmp)
        // Empty file should return empty string or error
        XCTAssertTrue(result.isEmpty || result.contains("Unable to read file"))
    }

    // MARK: - jsonEncode

    func testJsonEncodeSimpleString() {
        let result = HTMLBuilder.jsonEncode("hello")
        XCTAssertEqual(result, "\"hello\"")
    }

    func testJsonEncodeSpecialCharacters() {
        let result = HTMLBuilder.jsonEncode("line1\nline2")
        XCTAssertTrue(result.contains("\\n"))
    }

    func testJsonEncodeQuotes() {
        let result = HTMLBuilder.jsonEncode("say \"hi\"")
        XCTAssertTrue(result.contains("\\\""))
    }
}
