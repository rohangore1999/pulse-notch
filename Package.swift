// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PulseNotch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PulseNotch", targets: ["PulseNotch"])
    ],
    targets: [
        .executableTarget(
            name: "PulseNotch",
            path: "Sources/PulseNotch"
        ),
        .testTarget(
            name: "PulseNotchTests",
            dependencies: ["PulseNotch"],
            path: "Tests/PulseNotchTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
