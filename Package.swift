// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftNetworkPro",
    platforms: [
        .iOS(.v14),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v14),
    ],
    products: [
        .library(
            name: "SwiftNetworkPro",
            targets: ["SwiftNetworkPro"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftNetworkPro",
            dependencies: []
        ),
        .testTarget(
            name: "SwiftNetworkProTests",
            dependencies: ["SwiftNetworkPro"]
        ),
    ]
)