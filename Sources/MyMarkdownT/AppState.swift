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
    @Published var viewMode: ViewMode = .preview
    @Published private(set) var isDirty = false
    @Published var lastErrorMessage: String?
    @Published var transientNotice: String?

    private var lastSavedContent = ""
    private var isApplyingFileLoad = false
    private var transientNoticeTask: Task<Void, Never>?

    func openFilePanel() {
        guard let selected = FileService.chooseMarkdownFile() else {
            return
        }
        _ = handleIncomingItems([selected])
    }

    func openFolderPanel() {
        guard let selected = FileService.chooseFolder() else {
            return
        }

        revealFolder(selected)
    }

    @discardableResult
    func handleIncomingItems(_ urls: [URL]) -> Bool {
        let normalizedURLs = urls.map(\.standardizedFileURL)

        if let markdownFile = normalizedURLs.first(where: FileService.isMarkdownFile(_:)) {
            revealContext(for: markdownFile)
            openFile(at: markdownFile)
            return true
        }

        if let folder = normalizedURLs.first(where: FileService.isDirectory(_:)) {
            revealFolder(folder)
            return true
        }

        lastErrorMessage = "无法打开拖入或传入的项目。"
        return false
    }

    func refreshSidebar() {
        guard let root = sidebarRootURL else { return }
        sidebarNodes = FileService.buildTree(root: root)
    }

    func deleteNode(_ node: FileNode) {
        do {
            try FileService.deleteItem(at: node.url)
            if let current = currentFileURL {
                let deletedPath = node.url.standardizedFileURL.path
                let currentPath = current.path
                if currentPath == deletedPath || currentPath.hasPrefix(deletedPath + "/") {
                    currentFileURL = nil
                    content = ""
                    strippedContent = ""
                    headingAnchors = []
                }
            }
            refreshSidebar()
        } catch {
            lastErrorMessage = "删除失败，无法移至废纸篓。"
        }
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

    private func revealContext(for fileURL: URL) {
        let folderURL = fileURL.deletingLastPathComponent().standardizedFileURL
        let nodes = FileService.buildTree(root: folderURL)

        sidebarRootURL = folderURL
        if containsFile(fileURL, in: nodes) {
            sidebarNodes = nodes
        } else {
            sidebarNodes = [
                FileNode(
                    url: fileURL,
                    name: fileURL.lastPathComponent,
                    isDirectory: false,
                    children: nil
                )
            ]

            requestFolderAuthorization(for: fileURL)
        }
    }

    private func revealFolder(_ folderURL: URL) {
        sidebarRootURL = folderURL.standardizedFileURL
        sidebarNodes = FileService.buildTree(root: folderURL.standardizedFileURL)
    }

    private func containsFile(_ url: URL, in nodes: [FileNode]) -> Bool {
        let targetURL = url.standardizedFileURL
        for node in nodes {
            if node.url.standardizedFileURL == targetURL {
                return true
            }

            if let children = node.children, containsFile(targetURL, in: children) {
                return true
            }
        }

        return false
    }

    private func requestFolderAuthorization(for fileURL: URL) {
        let folderURL = fileURL.deletingLastPathComponent().standardizedFileURL
        guard let authorizedFolder = FileService.chooseFolder(
            startingAt: folderURL,
            message: "要浏览所在目录，请授权该文件夹",
            prompt: "授权文件夹"
        ) else {
            showTransientNotice("未授权文件夹访问，当前仅显示已打开文件")
            return
        }

        revealFolder(authorizedFolder)
        currentFileURL = fileURL.standardizedFileURL
        showTransientNotice("已授权文件夹访问")
    }

    private func showTransientNotice(_ message: String) {
        transientNoticeTask?.cancel()
        transientNotice = message

        transientNoticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                transientNotice = nil
            }
        }
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
