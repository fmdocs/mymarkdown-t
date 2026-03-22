import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

enum FileServiceError: Error {
    case noSelection
    case unreadable
    case unwritable
    case exportFailed
}

struct MarkdownLinkDestination: Equatable {
    let url: URL
    let fragment: String?
}

enum FileService {
    private static let markdownExtensions = ["md", "markdown", "mdx", "yfm"]
    private static let markdownContentTypes: [UTType] = {
        let contentTypes = markdownExtensions.compactMap {
            UTType(filenameExtension: $0, conformingTo: .text)
        }

        return contentTypes.isEmpty ? [.plainText] : contentTypes
    }()

    @MainActor
    static func chooseMarkdownFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = markdownContentTypes

        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseFolder() -> URL? {
        chooseFolder(startingAt: nil, message: nil, prompt: nil)
    }

    @MainActor
    static func chooseFolder(startingAt directoryURL: URL?, message: String?, prompt: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURL
        if let message {
            panel.message = message
        }
        if let prompt {
            panel.prompt = prompt
        }

        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseSaveLocation(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = markdownContentTypes
        panel.nameFieldStringValue = suggestedName

        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseExportLocation(suggestedName: String, fileExtension: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        if let contentType = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [contentType]
        }

        guard panel.runModal() == .OK, let selected = panel.url else {
            return nil
        }

        if selected.pathExtension.lowercased() == fileExtension.lowercased() {
            return selected
        }

        return selected.appendingPathExtension(fileExtension)
    }

    static func readText(from url: URL) throws -> String {
        try withSecurityScopedAccess(to: url) {
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw FileServiceError.unreadable
            }
        }
    }

    static func writeText(_ content: String, to url: URL) throws {
        try withSecurityScopedAccess(to: url) {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw FileServiceError.unwritable
            }
        }
    }

    static func writeData(_ data: Data, to url: URL) throws {
        try withSecurityScopedAccess(to: url) {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw FileServiceError.unwritable
            }
        }
    }

    static func deleteItem(at url: URL) throws {
        try withSecurityScopedAccess(to: url) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                throw FileServiceError.unwritable
            }
        }
    }

    @MainActor
    static func renderPDF(fromHTML html: String, baseURL: URL?) async throws -> Data {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1448))
        let delegate = PDFNavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: baseURL)

        try await delegate.waitForFinish()

        // 查询完整文档高度，确保 PDF 包含全部内容
        let fullHeight: CGFloat
        do {
            let result = try await webView.evaluateJavaScript("document.documentElement.scrollHeight")
            fullHeight = (result as? Double).map { CGFloat($0) } ?? 1448
        } catch {
            fullHeight = 1448
        }

        if fullHeight > webView.frame.height {
            webView.frame = NSRect(x: 0, y: 0, width: 1024, height: fullHeight)
            // 等待重新布局完成
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let configuration = WKPDFConfiguration()
        // 不设 configuration.rect，让 WebKit 渲染整个 webView 帧
        do {
            return try await webView.pdf(configuration: configuration)
        } catch {
            throw FileServiceError.exportFailed
        }
    }

    static func isMarkdownFile(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    static func resolveMarkdownLink(_ url: URL, relativeTo documentURL: URL?) -> MarkdownLinkDestination? {
        if let scheme = url.scheme {
            if scheme == "file" {
                return MarkdownLinkDestination(
                    url: URL(fileURLWithPath: url.path).standardizedFileURL,
                    fragment: normalizedFragment(url.fragment)
                )
            }
            return MarkdownLinkDestination(url: url, fragment: normalizedFragment(url.fragment))
        }

        let destination = url.relativeString
        guard let documentURL else {
            return nil
        }

        let parts = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(parts[0])
        let fragment = parts.count > 1 ? normalizedFragment(String(parts[1])) : nil

        guard !rawPath.isEmpty else {
            return MarkdownLinkDestination(url: documentURL.standardizedFileURL, fragment: fragment)
        }

        return MarkdownLinkDestination(
            url: URL(fileURLWithPath: rawPath, relativeTo: documentURL.deletingLastPathComponent())
                .standardizedFileURL,
            fragment: fragment
        )
    }

    private static func normalizedFragment(_ fragment: String?) -> String? {
        guard let fragment, !fragment.isEmpty else {
            return nil
        }

        return fragment.removingPercentEncoding ?? fragment
    }

    static func buildTree(root: URL) -> [FileNode] {
        let children: [URL]
        do {
            children = try withSecurityScopedAccess(to: root) {
                try FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            }
        } catch {
            return []
        }

        let sorted = children.sorted { lhs, rhs in
            lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }

        return sorted.compactMap { item in
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values?.isDirectory ?? false

            if isDirectory {
                let descendants = buildTree(root: item)
                if descendants.isEmpty {
                    return FileNode(
                        url: item,
                        name: item.lastPathComponent,
                        isDirectory: true,
                        children: []
                    )
                }
                return FileNode(
                    url: item,
                    name: item.lastPathComponent,
                    isDirectory: true,
                    children: descendants
                )
            }

            let ext = item.pathExtension.lowercased()
            guard markdownExtensions.contains(ext) else {
                return nil
            }

            return FileNode(
                url: item,
                name: item.lastPathComponent,
                isDirectory: false,
                children: nil
            )
        }
    }

    private static func withSecurityScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }
}

@MainActor
private final class PDFNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
