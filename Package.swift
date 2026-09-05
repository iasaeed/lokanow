// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Lokanow",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LocalizeCore", targets: ["LocalizeCore"]), .executable(name: "LokanowDev", targets: ["LokanowDev"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0")],
    targets: [
        .target(name: "LocalizeCore", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"), .product(name: "SwiftParser", package: "swift-syntax")]),
        .executableTarget(name: "LokanowDev", dependencies: ["LocalizeCore"], path: "Sources/Lokanow"),
        .testTarget(name: "LocalizeCoreTests", dependencies: ["LocalizeCore"])
    ],
    swiftLanguageModes: [.v5]
)
