import AppKit
import SwiftUI
import MarkdownUI

struct ContentView: View {
    @ObservedObject var state: AppState
    @State private var nodeToDelete: FileNode?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            workspace
        }
        .navigationTitle(title)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let transientNotice = state.transientNotice {
                noticeBanner(transientNotice)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .dropDestination(for: URL.self) { items, _ in
            state.handleIncomingItems(items)
        }
        .environment(\.openURL, OpenURLAction { url in
            state.openLink(url) ? .handled : .discarded
        })
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { state.goBack() }) {
                    Label("返回", systemImage: "chevron.left")
                }
                .disabled(!state.canGoBack)
                .help(breadcrumbTooltip)
            }

            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button("打开文件…") { state.openFilePanel() }
                    Button("打开文件夹…") { state.openFolderPanel() }
                } label: {
                    Label("打开", systemImage: "folder.badge.plus")
                }
                Button(action: { state.save() }) {
                    Text("保存")
                        .foregroundStyle(state.isDirty ? Color.white : Color.primary)
                        .fontWeight(state.isDirty ? .semibold : .regular)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(state.isDirty ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: state.isDirty)
            }

            ToolbarItem(placement: .automatic) {
                Picker("Mode", selection: $state.viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
        .alert(
            "错误",
            isPresented: Binding(
                get: { state.lastErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        state.lastErrorMessage = nil
                    }
                }
            )
        ) {
            Button("确定", role: .cancel) {
                state.lastErrorMessage = nil
            }
        } message: {
            Text(state.lastErrorMessage ?? "未知错误")
        }
    }

    private var sidebar: some View {
        List {
            if state.sidebarNodes.isEmpty {
                Text("打开文件夹以浏览 Markdown 文件")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.sidebarNodes) { node in
                    SidebarNodeRow(node: node, state: state, nodeToDelete: $nodeToDelete)
                }
            }
        }
        .confirmationDialog(
            "确认删除",
            isPresented: Binding(
                get: { nodeToDelete != nil },
                set: { if !$0 { nodeToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let node = nodeToDelete {
                Button("移至废纸篓", role: .destructive) {
                    state.deleteNode(node)
                    nodeToDelete = nil
                }
                Button("取消", role: .cancel) {
                    nodeToDelete = nil
                }
            }
        } message: {
            if let node = nodeToDelete {
                Text("\"\(node.name)\" 将被移至废纸篓")
            }
        }
    }

    private var workspace: some View {
        Group {
            switch state.viewMode {
            case .editor:
                editorPane
            case .preview:
                previewPane
            case .split:
                HSplitView {
                    editorPane
                    previewPane
                }
            }
        }
    }

    private var editorPane: some View {
        TextEditor(text: $state.content)
            .font(.system(.body, design: .monospaced))
            .padding(8)
    }

    private var previewPane: some View {
        let anchorResolver = HeadingAnchorResolver(anchors: state.headingAnchors)

        return ScrollViewReader { proxy in
            ScrollView {
                Markdown(
                    state.strippedContent,
                    baseURL: state.currentDocumentBaseURL,
                    imageBaseURL: state.currentDocumentBaseURL
                )
                .markdownTheme(.gitHub)
                .markdownImageProvider(LocalImageProvider())
                .markdownInlineImageProvider(LocalInlineImageProvider())
                .markdownBlockStyle(\.heading1) { configuration in
                    anchoredHeading(configuration, level: 1, resolver: anchorResolver)
                }
                .markdownBlockStyle(\.heading2) { configuration in
                    anchoredHeading(configuration, level: 2, resolver: anchorResolver)
                }
                .markdownBlockStyle(\.heading3) { configuration in
                    anchoredHeading(configuration, level: 3, resolver: anchorResolver)
                }
                .markdownBlockStyle(\.heading4) { configuration in
                    anchoredHeading(configuration, level: 4, resolver: anchorResolver)
                }
                .markdownBlockStyle(\.heading5) { configuration in
                    anchoredHeading(configuration, level: 5, resolver: anchorResolver)
                }
                .markdownBlockStyle(\.heading6) { configuration in
                    anchoredHeading(configuration, level: 6, resolver: anchorResolver)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .onAppear {
                scrollToPendingAnchor(using: proxy)
            }
            .onChange(of: state.scrollRequestID) {
                scrollToPendingAnchor(using: proxy)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func anchoredHeading(_ configuration: BlockConfiguration, level: Int, resolver: HeadingAnchorResolver) -> some View {
        let anchor = resolver.nextAnchor(for: configuration.content.renderPlainText())

        switch level {
        case 1:
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(2))
                    }
                Divider().overlay(Color.secondary.opacity(0.25))
            }
            .id(anchor)
        case 2:
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 24, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.5))
                    }
                Divider().overlay(Color.secondary.opacity(0.25))
            }
            .id(anchor)
        case 3:
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.25))
                }
                .id(anchor)
        case 4:
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                }
                .id(anchor)
        case 5:
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.875))
                }
                .id(anchor)
        default:
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.85))
                    ForegroundColor(.secondary)
                }
                .id(anchor)
        }
    }

    private func scrollToPendingAnchor(using proxy: ScrollViewProxy) {
        guard let anchor = state.pendingScrollAnchor, !anchor.isEmpty else {
            return
        }

        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    private var title: String {
        let name = state.currentFileURL?.lastPathComponent ?? "未命名"
        return state.isDirty ? "\(name) *" : name
    }

    private var breadcrumbTooltip: String {
        guard let last = state.navigationStack.last else { return "返回" }
        return "返回 \(last.lastPathComponent)"
    }

    private func noticeBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private final class HeadingAnchorResolver {
    private let anchorsByText: [String: [String]]
    private var nextIndexByText: [String: Int] = [:]

    init(anchors: [MarkdownHeadingAnchor]) {
        var grouped: [String: [String]] = [:]
        for anchor in anchors {
            grouped[anchor.text, default: []].append(anchor.anchor)
        }
        self.anchorsByText = grouped
    }

    func nextAnchor(for headingText: String) -> String {
        let anchors = anchorsByText[headingText] ?? [MarkdownRenderer.slug(from: headingText)]
        let index = nextIndexByText[headingText, default: 0]
        nextIndexByText[headingText] = index + 1

        if index < anchors.count {
            return anchors[index]
        }

        let fallback = anchors.last ?? MarkdownRenderer.slug(from: headingText)
        return "\(fallback)-\(index)"
    }
}

private struct LocalImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        LocalMarkdownImageView(url: url)
    }
}

private struct LocalMarkdownImageView: View {
    let url: URL?
    @State private var isPresentingPreview = false

    var body: some View {
        Group {
            if let url, url.isFileURL {
                if let image = NSImage(contentsOf: url) {
                    previewableImage(Image(nsImage: image))
                } else {
                    imagePlaceholder(message: "图片加载失败")
                }
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        imagePlaceholder(message: "正在加载图片...")
                    case .success(let image):
                        previewableImage(image)
                    case .failure:
                        imagePlaceholder(message: "图片加载失败")
                    default:
                        imagePlaceholder(message: "图片不可用")
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingPreview) {
            imagePreviewSheet
        }
    }

    private func previewableImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .onTapGesture {
                isPresentingPreview = true
            }
    }

    private func imagePlaceholder(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var imagePreviewSheet: some View {
        if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
            }
            .frame(minWidth: 800, minHeight: 600)
        } else {
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(24)
                    case .failure:
                        imagePlaceholder(message: "图片加载失败")
                            .padding(24)
                    default:
                        ProgressView("正在加载图片...")
                            .padding(24)
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 600)
        }
    }
}

private struct LocalInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        if url.isFileURL, let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = NSImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        return Image(nsImage: image)
    }
}

// MARK: - Sidebar recursive node view

private struct SidebarNodeRow: View {
    let node: FileNode
    @ObservedObject var state: AppState
    @Binding var nodeToDelete: FileNode?
    @State private var isExpanded = true

    var body: some View {
        if node.isDirectory, let children = node.children {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    SidebarNodeRow(node: child, state: state, nodeToDelete: $nodeToDelete)
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { isExpanded.toggle() }
                    }
            }
            .contextMenu {
                Button(role: .destructive) {
                    nodeToDelete = node
                } label: {
                    Label("移至废纸篓", systemImage: "trash")
                }
            }
        } else if !node.isDirectory {
            Label(node.name, systemImage: "doc.text")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(state.isCurrentFile(node.url) ? Color.accentColor.opacity(0.18) : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    state.openFile(at: node.url)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        nodeToDelete = node
                    } label: {
                        Label("移至废纸篓", systemImage: "trash")
                    }
                }
        }
    }
}
