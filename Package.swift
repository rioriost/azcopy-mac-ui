// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "azcopy-mac-ui",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AzCopyMacUICore", targets: ["AzCopyMacUICore"]),
        .executable(name: "AzCopyMacUI", targets: ["AzCopyMacUI"])
    ],
    targets: [
        .target(name: "AzCopyMacUICore"),
        .executableTarget(
            name: "AzCopyMacUI",
            dependencies: ["AzCopyMacUICore"]
        ),
        .testTarget(
            name: "AzCopyMacUICoreTests",
            dependencies: ["AzCopyMacUICore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
