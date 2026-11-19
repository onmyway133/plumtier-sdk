// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Plumtier",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Plumtier", targets: ["Plumtier"]),
    ],
    targets: [
        .target(name: "Plumtier"),
        .testTarget(name: "PlumtierTests", dependencies: ["Plumtier"]),
    ]
)
