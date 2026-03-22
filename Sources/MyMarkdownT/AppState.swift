import AppKit
import Foundation

enum ViewMode: String, CaseIterable, Identifiable {
    case editor
    case split
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor:
            return "编辑"
        case .split:
            return "分栏"
        case .preview:
            return "预览"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var content: String = "" {
        didSet {
            guard !isApplyingFileLoad else { return }
            isDirty = content != lastSavedContent
            refreshRenderedContent()
        }
    }

    @Published private(set) var strippedContent: String = ""
    @Published private(set) var headingAnchors: [MarkdownHeadingAnchor] = []
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var sidebarRootURL: URL?
    @Published private(set) var sidebarNodes: [FileNode] = []
    @Published private(set) var pendingScrollAnchor: String?
    @Published private(set) var scrollRequestID = UUID()
    @Published var viewMode: ViewMode = .split
    @Published private(set) var isDirty = false
    @Published var lastErrorMessage: String?

    private var lastSavedContent = ""
    private var isApplyingFileLoad = false

    func openFilePanel() {
        guard let selected = FileService.chooseMarkdownFile() else {
            return
        }
        openFile(at: selected)
    }

    func openFolderPanel() {
        guard let selected = FileService.chooseFolder() else {
            return
        }

        sidebarRootURL = selected
        sidebarNodes = FileService.buildTree(root: selected)
    }

    func openFile(at url: URL, anchor: String? = nil) {
        let normalizedURL = url.standardizedFileURL

        do {
            currentFileURL = normalizedURL
            let text = try FileService.readText(from: normalizedURL)
            applyLoadedContent(text)
            requestScroll(to: anchor)
        } catch {
            lastErrorMessage = "无法打开文件。"
        }
    }

    func save() {
        if let fileURL = currentFileURL {
            persist(to: fileURL)
            return
        }
        saveAs()
    }

    func saveAs() {
        let preferredName = currentFileURL?.lastPathComponent ?? "untitled.md"
        guard let destination = FileService.chooseSaveLocation(suggestedName: preferredName) else {
            return
        }

        persist(to: destination)
        currentFileURL = destination
    }

    private func persist(to url: URL) {
        do {
            try FileService.writeText(content, to: url)
            lastSavedContent = content
            isDirty = false
        } catch {
            lastErrorMessage = "无法保存文件。"
        }
    }

    func exportHTML() {
        let baseName = (currentFileURL?.deletingPathExtension().lastPathComponent ?? "untitled") + ".html"
        guard let destination = FileService.chooseExportLocation(suggestedName: baseName, fileExtension: "html") else {
            return
        }

        let html = MarkdownRenderer.renderHTMLDocument(markdown: content, baseURL: currentDocumentBaseURL)
        do {
            try FileService.writeText(html, to: destination)
        } catch {
            lastErrorMessage = "导出 HTML 失败。"
        }
    }

    func exportPDF() {
        let baseName = (currentFileURL?.deletingPathExtension().lastPathComponent ?? "untitled") + ".pdf"
        guard let destination = FileService.chooseExportLocation(suggestedName: baseName, fileExtension: "pdf") else {
            return
        }

        let html = MarkdownRenderer.renderHTMLDocument(markdown: content, baseURL: currentDocumentBaseURL)
        Task { @MainActor in
            do {
                let pdfData = try await FileService.renderPDF(fromHTML: html, baseURL: currentDocumentBaseURL)
                try FileService.writeData(pdfData, to: destination)
            } catch {
                lastErrorMessage = "导出 PDF 失败。"
            }
        }
    }

    @discardableResult
    func openLink(_ url: URL) -> Bool {
        guard let destination = FileService.resolveMarkdownLink(url, relativeTo: currentFileURL) else {
            lastErrorMessage = "无法解析链接。"
            return false
        }

        let anchor = destination.fragment

        if destination.url == currentFileURL {
            requestScroll(to: anchor)
            return true
        }

        if destination.url.isFileURL, FileService.isMarkdownFile(destination.url) {
            guard FileManager.default.fileExists(atPath: destination.url.path) else {
                lastErrorMessage = "链接指向的 Markdown 文件不存在。"
                return false
            }
            openFile(at: destination.url, anchor: anchor)
            return true
        }

        return NSWorkspace.shared.open(destination.url)
    }

    var currentDocumentBaseURL: URL? {
        currentFileURL?.deletingLastPathComponent()
    }

    func isCurrentFile(_ url: URL) -> Bool {
        currentFileURL == url.standardizedFileURL
    }

    private func requestScroll(to anchor: String?) {
        pendingScrollAnchor = anchor
        scrollRequestID = UUID()
    }

    private func applyLoadedContent(_ text: String) {
        isApplyingFileLoad = true
        content = text
        refreshRenderedContent()
        lastSavedContent = text
        isDirty = false
        isApplyingFileLoad = false
    }

    private func refreshRenderedContent() {
        let rendered = MarkdownRenderer.prepare(markdown: content, baseURL: currentDocumentBaseURL)
        strippedContent = rendered.markdown
        headingAnchors = rendered.headingAnchors
    }
}
