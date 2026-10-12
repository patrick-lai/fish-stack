// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FishStack",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FishStack", targets: ["FishStack"])],
    targets: [
        .executableTarget(name: "FishStack", path: "Sources/FishStack"),
        .testTarget(name: "FishStackTests", dependencies: ["FishStack"], path: "Tests/FishStackTests"),
    ]
)
