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
        )
    ],
    targets: [
        .target(
            name: "PeerConnectivity",
            dependencies: [],
            path: "Sources"
        )
    ],
    swiftLanguageVersions: [.v5]
)
