// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIGossip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIGossip", targets: ["AIGossip"]),
    ],
    targets: [
        .executableTarget(
            name: "AIGossip",
            path: "Sources/AIGossip"
        ),
    ]
)
