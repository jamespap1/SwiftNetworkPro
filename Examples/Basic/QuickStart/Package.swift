// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickStart",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../../../")
    ],
    targets: [
        .executableTarget(
            name: "QuickStart",
            dependencies: ["SwiftNetworkPro"],
            path: "Sources"
        )
    ]
)