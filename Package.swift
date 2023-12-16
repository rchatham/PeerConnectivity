// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "PeerConnectivity",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_13)
    ],
    products: [
        .library(name: "PeerConnectivity", targets: ["PeerConnectivity"])
    ],
    targets: [
        .target(
            name: "PeerConnectivity"
        ),
        .testTarget(
            name: "PeerConnectivityTests",
            dependencies: ["PeerConnectivity"]
        )
    ]
)
