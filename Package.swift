// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NeurIPSTalks",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NeurIPSTalks", targets: ["NeurIPSTalks"])],
    targets: [
        .executableTarget(
            name: "NeurIPSTalks",
            path: "Sources/NeurIPSTalks"
        ),
        .testTarget(
            name: "NeurIPSTalksTests",
            dependencies: ["NeurIPSTalks"],
            path: "Tests/NeurIPSTalksTests"
        )
    ]
)
