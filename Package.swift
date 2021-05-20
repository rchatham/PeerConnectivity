// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "PeerConnectivity",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "PeerConnectivity",
            targets: ["PeerConnectivity"]),
    ],
    dependencies: [
        .package(name: "Logger", url: "git@github.com:tillersystems/logger-ios.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "PeerConnectivity",
            dependencies: ["Logger"],
            path: "Sources"
        ),
        .testTarget(
            name: "PeerConnectivityTests",
            dependencies: ["PeerConnectivity"],
            path: "PeerConnectivityTests"
        ),
    ]
)
