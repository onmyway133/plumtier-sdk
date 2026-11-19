// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlumtierExample",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(name: "PlumtierExample", dependencies: [.product(name: "Plumtier", package: "plumtier-sdk")]),
    ]
)
