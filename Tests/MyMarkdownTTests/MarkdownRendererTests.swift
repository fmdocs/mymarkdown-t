import XCTest
@testable import MyMarkdownT

final class MarkdownRendererTests: XCTestCase {
    func testStripFrontMatterWhenPresent() {
        let input = """
        ---
        title: Example
        tags:
          - demo
        ---
        # Hello
        """

        let output = MarkdownRenderer.stripFrontMatter(input)

        XCTAssertEqual(output, "# Hello")
    }

    func testKeepTextWhenNoFrontMatter() {
        let input = "# Plain"
        let output = MarkdownRenderer.stripFrontMatter(input)
        XCTAssertEqual(output, "# Plain")
    }

    func testResolveRelativeMarkdownLinkAgainstCurrentDocument() {
        let documentURL = URL(fileURLWithPath: "/tmp/docs/guide/index.md")
        let linkURL = URL(string: "./syntax/notes.md")!

        let destination = FileService.resolveMarkdownLink(linkURL, relativeTo: documentURL)

        XCTAssertEqual(destination?.url.path, "/tmp/docs/guide/syntax/notes.md")
        XCTAssertNil(destination?.fragment)
    }

    func testResolveAnchorLinkToCurrentDocument() {
        let documentURL = URL(fileURLWithPath: "/tmp/docs/guide/index.md")
        let linkURL = URL(string: "#section-1")!

        let destination = FileService.resolveMarkdownLink(linkURL, relativeTo: documentURL)

        XCTAssertEqual(destination?.url, documentURL)
        XCTAssertEqual(destination?.fragment, "section-1")
    }

    func testKeepExternalLinkUntouched() {
        let linkURL = URL(string: "https://example.com/docs")!

        let destination = FileService.resolveMarkdownLink(linkURL, relativeTo: nil)

        XCTAssertEqual(destination?.url, linkURL)
    }

    func testResolveRelativeMarkdownLinkKeepsFragment() {
        let documentURL = URL(fileURLWithPath: "/tmp/docs/guide/index.md")
        let linkURL = URL(string: "./syntax/notes.md#%E6%A0%87%E9%A2%98")!

        let destination = FileService.resolveMarkdownLink(linkURL, relativeTo: documentURL)

        XCTAssertEqual(destination?.url.path, "/tmp/docs/guide/syntax/notes.md")
        XCTAssertEqual(destination?.fragment, "标题")
    }

    func testGenerateHeadingSlugForChineseAndEnglish() {
        XCTAssertEqual(MarkdownRenderer.slug(from: "标题"), "标题")
        XCTAssertEqual(MarkdownRenderer.slug(from: "Hello, World!"), "hello-world")
    }

    func testGenerateUniqueHeadingAnchorsLikeGitHub() {
        let markdown = """
        # 标题
        ## 标题
        # Hello World
        ## Hello World
        """

        let anchors = MarkdownRenderer.headingAnchors(in: markdown)

        XCTAssertEqual(
            anchors.map(\.anchor),
            ["标题", "标题-1", "hello-world", "hello-world-1"]
        )
    }

    func testGenerateHeadingAnchorsSupportsSetextHeadings() {
        let markdown = """
        Title
        =====

        Subtitle
        -----
        """

        let anchors = MarkdownRenderer.headingAnchors(in: markdown)

        XCTAssertEqual(anchors.map(\.anchor), ["title", "subtitle"])
    }

    func testPrepareTransformsNoteAndCutDirectives() {
        let markdown = """
        {% note warning "风险" %}
        注意配置。
        {% endnote %}

        {% cut "更多信息" %}
        隐藏内容
        {% endcut %}
        """

        let rendered = MarkdownRenderer.prepare(markdown: markdown, baseURL: nil)

        XCTAssertTrue(rendered.markdown.contains("> [!WARNING] 风险"))
        XCTAssertTrue(rendered.markdown.contains("> **折叠：更多信息**"))
    }

    func testPrepareTransformsTabsAndFileDirective() {
        let markdown = """
        {% list tabs %}

        - macOS

          brew install demo

        - Linux

          apt install demo

        {% endlist %}

        {% file src="https://example.com/a.txt" name="a.txt" %}
        """

        let rendered = MarkdownRenderer.prepare(markdown: markdown, baseURL: nil)

        XCTAssertTrue(rendered.markdown.contains("### macOS"))
        XCTAssertTrue(rendered.markdown.contains("brew install demo"))
        XCTAssertTrue(rendered.markdown.contains("[下载 a.txt](https://example.com/a.txt)"))
    }

    func testPrepareTransformsCustomHeadingAnchors() {
        let markdown = """
        ## 第一章 {#custom-anchor}
        ## 第一章
        """

        let rendered = MarkdownRenderer.prepare(markdown: markdown, baseURL: nil)

        XCTAssertEqual(rendered.headingAnchors.map(\.anchor), ["custom-anchor", "第一章-1"])
    }

    func testPrepareTransformsMultilineSimpleTableToGFM() {
        let markdown = """
        #|
        || 标题1 | 标题2 ||
        || 文本A | 文本B ||
        |#
        """

        let rendered = MarkdownRenderer.prepare(markdown: markdown, baseURL: nil)

        XCTAssertTrue(rendered.markdown.contains("| 标题1 | 标题2 |"))
        XCTAssertTrue(rendered.markdown.contains("| --- | --- |"))
        XCTAssertTrue(rendered.markdown.contains("| 文本A | 文本B |"))
    }

    func testPrepareTransformsVideoSyntaxToLink() {
        let markdown = "@[youtube](https://example.com/video)"

        let rendered = MarkdownRenderer.prepare(markdown: markdown, baseURL: nil)

        XCTAssertEqual(rendered.markdown, "[视频（youtube）](https://example.com/video)")
    }

    func testRenderHTMLDocumentContainsHTMLSkeleton() {
        let html = MarkdownRenderer.renderHTMLDocument(markdown: "# 标题", baseURL: nil)

        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<html lang=\"zh-CN\">"))
        XCTAssertTrue(html.contains("<body>"))
    }

    func testPrepareReplacesTermDefinitionAndMonospace() {
        let markdown = """
        [*term]: 术语定义
        在文本中使用[术语](*term)以及##等宽文本##。
        """

        let rendered = MarkdownRenderer.prepare(markdown: markdown, baseURL: nil)

        XCTAssertTrue(rendered.markdown.contains("术语（术语定义）"))
        XCTAssertTrue(rendered.markdown.contains("`等宽文本`"))
    }
}
