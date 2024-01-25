// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftNetworkPro",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .watchOS(.v9),
        .tvOS(.v15),
        .visionOS(.v1)
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