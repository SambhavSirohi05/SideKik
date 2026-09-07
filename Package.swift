// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SideKik",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SideKik",
            targets: ["SideKik"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SideKik",
            path: "Sources/SideKik",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
