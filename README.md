# mymarkdown-t

一个面向 macOS 的原生 Markdown 编辑器原型，使用 SwiftUI + AppKit 实现。该项目当前同时保留两条开发路径：
- Swift Package Manager：用于快速构建、运行与测试
- Xcode App 工程：用于签名、归档与分发

## 项目目标

当前阶段聚焦于验证桌面编辑器的基础能力和工程结构，目标包括：
- 提供原生 macOS Markdown 编辑与预览体验
- 保持 SwiftPM 驱动的轻量开发循环
- 提供可复现的 Xcode 工程定义，便于后续归档与发布

## 当前能力

已实现功能：
- 打开 Markdown 文件
- 编辑内容
- 原生 Markdown 预览（MarkdownUI）
- 保存 / 另存为
- 导出 HTML / PDF
- Markdown 文件夹树
- 视图模式：编辑 / 分栏 / 预览

当前尚未覆盖：
- 导出能力
- 更完整的文档类型集成
- 签名、沙箱、图标和发布自动化

## 技术栈

- Swift 6
- SwiftUI：窗口与界面结构
- AppKit：文件选择和保存面板
- MarkdownUI：GFM 兼容渲染
- WebKit：PDF 导出渲染
- Swift Package Manager：构建与测试
- XcodeGen：生成可分发的 Xcode 工程

## 环境要求

- macOS 15 或更高版本
- Xcode 16 或更新版本
- Swift tools 6.2.4
- 如需生成 Xcode 工程：XcodeGen

## 目录结构

```text
mymarkdown-t/
├── Package.swift
├── README.md
├── project.yml
├── Sources/MyMarkdownT/
│   ├── MyMarkdownTApp.swift
│   ├── ContentView.swift
│   ├── AppState.swift
│   ├── FileService.swift
│   ├── FileNode.swift
│   └── MarkdownRenderer.swift
├── Tests/MyMarkdownTTests/
│   └── MarkdownRendererTests.swift
├── Xcode/
│   ├── Config/
│   └── Support/
└── scripts/
```

## 核心模块

- `MyMarkdownTApp.swift`：SwiftUI App 入口
- `ContentView.swift`：主界面、工具栏、三种视图模式
- `AppState.swift`：编辑状态、当前文件、错误状态和保存流程
- `FileService.swift`：文件打开、保存、目录扫描
- `MarkdownRenderer.swift`：去除 front matter 并渲染 Markdown
- `MarkdownRendererTests.swift`：当前渲染逻辑测试

## 构建

```bash
cd mymarkdown-t
swift build
```

## 运行

```bash
cd mymarkdown-t
swift run
```

## 导出

在应用工具栏中可以直接使用：
- `导出 HTML`
- `导出 PDF`

导出内容基于当前页面的渲染结果（包含 YFM 预处理后的内容）。

## 测试

```bash
cd mymarkdown-t
swift test
```

当前测试覆盖：
- YAML front matter 存在时的剥离逻辑
- 无 front matter 时的原文保留逻辑

## Xcode App 工程

仓库包含一套可复现的 Xcode 工程定义，用于 macOS App 分发，而不是直接提交手工维护的 `.xcodeproj`。

采用这套结构的原因：
- 保留 SwiftPM，用于快速的命令行构建和测试循环。
- Xcode App 配置保存在可版本管理的配置文件中，而不是手动编辑的 `.xcodeproj`。
- 生成出来的 App target 可以直接在 Xcode 中归档、签名和分发。

### 文件说明

- `project.yml`：XcodeGen 工程描述文件
- `Xcode/Config/Base.xcconfig`：Bundle Identifier、版本号、签名团队
- `Xcode/Config/Debug.xcconfig`：Debug 配置扩展
- `Xcode/Config/Release.xcconfig`：Release 配置扩展
- `Xcode/Support/Info.plist`：应用元数据和 Markdown 文档类型注册
- `scripts/generate_xcodeproj.sh`：生成 Xcode 工程的辅助脚本

### 生成 Xcode 工程

先安装一次 XcodeGen：

```bash
brew install xcodegen
```

生成工程：

```bash
cd mymarkdown-t
./scripts/generate_xcodeproj.sh
open MyMarkdownT.xcodeproj
```

生成完成后，可以直接在 Xcode 中：
- 运行 App
- 调整签名设置
- 执行 Archive
- 导出分发包

### 为分发做配置

归档之前，请先更新 `Xcode/Config/Base.xcconfig` 中的这些值：
- `PRODUCT_BUNDLE_IDENTIFIER`
- `DEVELOPMENT_TEAM`
- `MARKETING_VERSION`
- `CURRENT_PROJECT_VERSION`

然后可以使用 Xcode 或命令行归档：

```bash
xcodebuild -project MyMarkdownT.xcodeproj -scheme MyMarkdownT -configuration Release archive
```

更完整的发布步骤可以参考 `RELEASE.md`。

## 开发建议

- 日常开发优先使用 `swift build`、`swift run`、`swift test`
- 需要检查签名、Bundle 配置和 Archive 流程时再生成 Xcode 工程
- 配置项尽量放在 `xcconfig` 中，不要把环境相关值散落到源码里

## 当前已验证项

- `swift package resolve` 通过
- `swift build` 通过
- `swift test` 通过
- `swift run` 可正常启动
- HTML / PDF 导出流程可用

## 说明

- 这是第一阶段的实现。
- 当前 YFM 支持采用预处理方式，覆盖了核心语法（如 note/cut/tabs/file、自定义标题锚点、术语引用、{#T} 自动标题、图片尺寸语法兼容等）。
