import XCTest
@testable import MyMarkdownT

final class MarkdownBlockParserTests: XCTestCase {

    // MARK: - Basic parsing

    func testEmptyContent() {
        let blocks = MarkdownBlockParser.parse("")
        XCTAssertTrue(blocks.isEmpty)
    }

    func testSingleHeading() {
        let blocks = MarkdownBlockParser.parse("# Hello")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .heading)
        XCTAssertEqual(blocks[0].text, "# Hello")
    }

    func testHeadingAndParagraph() {
        let input = """
        # Title

        Some body text here.
        """
        let blocks = MarkdownBlockParser.parse(input)
        // heading, separator, paragraph
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].blockType, .heading)
        XCTAssertEqual(blocks[1].blockType, .separator)
        XCTAssertEqual(blocks[2].blockType, .paragraph)
    }

    func testMultipleParagraphs() {
        let input = """
        First paragraph.

        Second paragraph.
        """
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].text, "First paragraph.")
        XCTAssertEqual(blocks[1].blockType, .separator)
        XCTAssertEqual(blocks[2].text, "Second paragraph.")
    }

    // MARK: - Code blocks

    func testFencedCodeBlockWithBlankLines() {
        let input = """
        ```swift
        let x = 1

        let y = 2
        ```
        """
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .codeBlock)
        XCTAssertTrue(blocks[0].text.contains("let x = 1"))
        XCTAssertTrue(blocks[0].text.contains("let y = 2"))
    }

    func testTildeFencedCodeBlock() {
        let input = """
        ~~~
        code here
        ~~~
        """
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .codeBlock)
    }

    func testCodeBlockBetweenParagraphs() {
        let input = """
        Before code.

        ```
        code
        ```

        After code.
        """
        let blocks = MarkdownBlockParser.parse(input)
        // paragraph, sep, codeBlock, sep, paragraph
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0].blockType, .paragraph)
        XCTAssertEqual(blocks[2].blockType, .codeBlock)
        XCTAssertEqual(blocks[4].blockType, .paragraph)
    }

    // MARK: - Block type detection

    func testListDetection() {
        let input = "- item 1\n- item 2\n- item 3"
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .list)
    }

    func testOrderedListDetection() {
        let input = "1. first\n2. second"
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .list)
    }

    func testBlockquoteDetection() {
        let input = "> This is a quote\n> continued"
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .blockquote)
    }

    func testTableDetection() {
        let input = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .table)
    }

    func testHorizontalRuleDetection() {
        for rule in ["---", "***", "___", "- - -", "* * *"] {
            let blocks = MarkdownBlockParser.parse(rule)
            XCTAssertEqual(blocks[0].blockType, .horizontalRule, "Failed for: \(rule)")
        }
    }

    func testHeadingLevels() {
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            let blocks = MarkdownBlockParser.parse("\(prefix) Heading \(level)")
            XCTAssertEqual(blocks[0].blockType, .heading, "Failed for H\(level)")
        }
    }

    // MARK: - isMultiLine

    func testMultiLineProperty() {
        XCTAssertTrue(MarkdownBlock(id: UUID(), text: "", blockType: .codeBlock).isMultiLine)
        XCTAssertTrue(MarkdownBlock(id: UUID(), text: "", blockType: .list).isMultiLine)
        XCTAssertTrue(MarkdownBlock(id: UUID(), text: "", blockType: .table).isMultiLine)
        XCTAssertTrue(MarkdownBlock(id: UUID(), text: "", blockType: .blockquote).isMultiLine)
        XCTAssertFalse(MarkdownBlock(id: UUID(), text: "", blockType: .heading).isMultiLine)
        XCTAssertFalse(MarkdownBlock(id: UUID(), text: "", blockType: .paragraph).isMultiLine)
    }

    // MARK: - Reconstruction

    func testReconstructRoundTrip() {
        let input = """
        # Title

        Some text here.

        ```swift
        let x = 1
        ```

        - item 1
        - item 2
        """
        let blocks = MarkdownBlockParser.parse(input)
        let reconstructed = MarkdownBlockParser.reconstruct(blocks)
        XCTAssertEqual(reconstructed, input)
    }

    func testReconstructSimple() {
        let blocks = [
            MarkdownBlock(id: UUID(), text: "# Hello", blockType: .heading),
            MarkdownBlock(id: UUID(), text: "", blockType: .separator),
            MarkdownBlock(id: UUID(), text: "World", blockType: .paragraph),
        ]
        let result = MarkdownBlockParser.reconstruct(blocks)
        XCTAssertEqual(result, "# Hello\n\nWorld")
    }

    // MARK: - Edge cases

    func testUnclosedCodeFence() {
        let input = """
        ```
        unclosed code
        some more
        """
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .codeBlock)
    }

    func testConsecutiveBlankLines() {
        let input = "A\n\n\n\nB"
        let blocks = MarkdownBlockParser.parse(input)
        // A, sep, sep, sep, B
        let nonSep = blocks.filter { $0.blockType != .separator }
        XCTAssertEqual(nonSep.count, 2)
        XCTAssertEqual(nonSep[0].text, "A")
        XCTAssertEqual(nonSep[1].text, "B")
    }

    func testMultiLineParagraph() {
        let input = "Line one\nLine two\nLine three"
        let blocks = MarkdownBlockParser.parse(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].blockType, .paragraph)
        XCTAssertEqual(blocks[0].text, input)
    }
}
