// swift-tools-version: 6.2.4
import PackageDescription

let package = Package(
    name: "mymarkdown-t",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "mymarkdown-t", targets: ["MyMarkdownT"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyMarkdownT",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "Sources/MyMarkdownT"
        ),
        .testTarget(
            name: "MyMarkdownTTests",
            dependencies: ["MyMarkdownT"],
            path: "Tests/MyMarkdownTTests"
        )
    ]
)
