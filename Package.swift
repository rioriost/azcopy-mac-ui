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
        )
    ],
    swiftLanguageModes: [.v6]
)
