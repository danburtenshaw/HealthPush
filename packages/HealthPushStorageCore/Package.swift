// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HealthPushStorageCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "HealthPushStorageCore",
            targets: ["HealthPushStorageCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.3.1")
    ],
    targets: [
        .target(
            name: "HealthPushStorageCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "HealthPushStorageCoreTests",
            dependencies: ["HealthPushStorageCore"]
        )
    ]
)
