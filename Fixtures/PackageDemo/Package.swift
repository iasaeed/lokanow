// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PackageDemo", defaultLocalization: "en", platforms: [.macOS(.v14)], products: [.library(name: "Checkout", targets: ["Checkout"])], targets: [.target(name: "Checkout", resources: [.process("Resources")]), .testTarget(name: "CheckoutTests", dependencies: ["Checkout"])])
