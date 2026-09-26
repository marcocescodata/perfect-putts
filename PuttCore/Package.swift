// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PuttCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PuttCore", targets: ["PuttCore"]),
    ],
    targets: [
        .target(name: "PuttCore"),
        .testTarget(name: "PuttCoreTests", dependencies: ["PuttCore"]),
    ]
)
