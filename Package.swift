// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PeerConnectivity",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "PeerConnectivity",
            targets: ["PeerConnectivity"]
        ),
        .library(
            name: "PeerConnectivityUI",
            targets: ["PeerConnectivityUI"]
        )
    ],
    targets: [
        .target(
            name: "PeerConnectivity",
            dependencies: [],
            path: "Sources",
            exclude: ["PeerConnectivityUI"]
        ),
        .target(
            name: "PeerConnectivityUI",
            dependencies: ["PeerConnectivity"],
            path: "Sources/PeerConnectivityUI"
        ),
        .testTarget(
            name: "PeerConnectivityTests",
            dependencies: ["PeerConnectivity"],
            path: "PeerConnectivityTests",
            exclude: ["Info.plist"]
        )
    ],
    swiftLanguageModes: [.v5]
)
