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
    ],
    targets: [
        .target(
            name: "PeerConnectivity",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "PeerConnectivityTests",
            dependencies: ["PeerConnectivity"],
            path: "PeerConnectivityTests"
        ),
    ]
)
