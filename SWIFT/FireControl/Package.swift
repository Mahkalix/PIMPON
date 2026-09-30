// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FireControlCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FireControlCore", targets: ["FireControlCore"])],
    targets: [
        .target(name: "FireControlCore"),
        .testTarget(name: "FireControlCoreTests", dependencies: ["FireControlCore"])
    ],
    swiftLanguageModes: [.v5]
)
