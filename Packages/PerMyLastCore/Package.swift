// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerMyLastCore",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "PerMyLastCore", targets: ["PerMyLastCore"])
    ],
    targets: [
        .target(name: "PerMyLastCore"),
        .testTarget(name: "PerMyLastCoreTests", dependencies: ["PerMyLastCore"])
    ]
)
