# mymarkdown-t 发布说明

本文档说明如何为 MyMarkdownT 生成可签名、可归档、可分发的 macOS App。

## 目标

当前仓库采用两套并行工作流：
- SwiftPM：用于日常开发、构建、运行和测试
- Xcode 工程：用于签名、Archive 和分发

发布流程基于 XcodeGen 生成的工程，而不是直接维护 `.xcodeproj`。

## 前置条件

- 已安装 Xcode
- 已安装命令行工具
- 已安装 XcodeGen
- 拥有可用的 Apple Developer 账号
- 拥有用于签名的 Team

安装 XcodeGen：

```bash
brew install xcodegen
```

## 发布前配置

发布前先检查这些文件：
- `project.yml`
- `Xcode/Config/Base.xcconfig`
- `Xcode/Support/Info.plist`

其中最关键的是 `Xcode/Config/Base.xcconfig`：

```xcconfig
PRODUCT_BUNDLE_IDENTIFIER = com.example.MyMarkdownT
PRODUCT_NAME = MyMarkdownT
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1
DEVELOPMENT_TEAM =
```

发布前至少需要确认：
- `PRODUCT_BUNDLE_IDENTIFIER` 已替换为正式包名
- `DEVELOPMENT_TEAM` 已填写实际团队 ID
- `MARKETING_VERSION` 已设置为本次发布版本
- `CURRENT_PROJECT_VERSION` 已递增

## 生成 Xcode 工程

在仓库根目录执行：

```bash
cd mymarkdown-t
./scripts/generate_xcodeproj.sh
```

生成完成后会得到：

```bash
MyMarkdownT.xcodeproj
```

然后打开工程：

```bash
open MyMarkdownT.xcodeproj
```

## 在 Xcode 中检查签名

打开工程后，检查 `MyMarkdownT` target：

1. 进入 `Signing & Capabilities`
2. 确认 Team 正确
3. 确认 Bundle Identifier 正确
4. 确认 `Automatically manage signing` 已开启

如果后续需要沙箱、文件访问权限或其他能力，再在这里继续补充。

## 本地验证

在归档之前，建议先跑一遍基础验证：

```bash
cd mymarkdown-t
swift build
swift test
swift run
```

如果使用 Xcode 工程验证，也可以执行：

```bash
xcodebuild -project MyMarkdownT.xcodeproj -scheme MyMarkdownT -configuration Debug build
```

## Archive

可以在 Xcode 中通过 `Product > Archive` 归档，也可以使用命令行：

```bash
xcodebuild \
  -project MyMarkdownT.xcodeproj \
  -scheme MyMarkdownT \
  -configuration Release \
  archive
```

如果希望明确指定归档输出路径：

```bash
xcodebuild \
  -project MyMarkdownT.xcodeproj \
  -scheme MyMarkdownT \
  -configuration Release \
  -archivePath build/MyMarkdownT.xcarchive \
  archive
```

归档成功后，产物通常位于：

```bash
build/MyMarkdownT.xcarchive
```

## 导出与分发

当前仓库已经具备生成和归档能力，但导出策略可以按你的分发渠道再细化：
- 本地分发
- Developer ID 签名分发
- Mac App Store 分发

如果只是本地验证归档是否成功，优先在 Xcode Organizer 中查看 Archive 是否可用。

如果要做正式导出，通常还需要进一步补齐：
- 导出用的 `ExportOptions.plist`
- App Sandbox 和 entitlements
- 图标资源
- 公证与 stapling 流程

## 建议的发布检查清单

每次发布前建议检查：

1. 版本号和构建号已更新
2. Bundle Identifier 和 Team 正确
3. `swift build` 和 `swift test` 通过
4. App 能正常启动并完成基本文件打开、编辑、保存流程
5. Release Archive 可以成功生成

## 后续可扩展项

如果要把发布流程继续完善，下一步通常会补这些内容：
- `MyMarkdownT.entitlements`
- `ExportOptions.plist`
- `scripts/archive.sh`
- `scripts/export.sh`
- 公证与 stapling 自动化脚本
