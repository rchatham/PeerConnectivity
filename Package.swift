// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "PeerConnectivity",
    platforms: [
        .iOS(.v8),
        .macOS(.v10_10),
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
    swiftLanguageVersions: [.v5]
)
