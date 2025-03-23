// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "gemini-ios",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)  // 更新为macOS 12.0以支持MarkdownUI
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "gemini-ios",
            targets: ["gemini-ios"]),
    ],
    dependencies: [
        // 添加MarkdownUI依赖
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "gemini-ios",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]),
        .testTarget(
            name: "gemini-iosTests",
            dependencies: ["gemini-ios"]),
    ]
)
