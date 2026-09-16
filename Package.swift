// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "azcopy-mac-ui",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AzCopyMacUICore", targets: ["AzCopyMacUICore"])
    ],
    targets: [
        .target(name: "AzCopyMacUICore"),
        .testTarget(
            name: "AzCopyMacUICoreTests",
            dependencies: ["AzCopyMacUICore"]
        ),
        .target(
            name: "AzCopyMacUIModel",
            dependencies: ["AzCopyMacUICore"],
            path: "Sources/AzCopyMacUI",
            exclude: ["AzCopyMacUIApp.swift", "ContentView.swift"]
        ),
        .testTarget(
            name: "AzCopyMacUIModelTests",
            dependencies: ["AzCopyMacUIModel", "AzCopyMacUICore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
