// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MIOAWSS3",
    platforms: [
        .iOS( .v13 ),
        .macOS( .v12 ),
    ],
    products: [
        .library(
            name: "MIOAWSS3",
            targets: ["MIOAWSS3"]
        ),
        .library(
            name: "MIOAWSCore",
            targets: ["MIOAWSCore"]
        ),
    ],
    dependencies: [
        .package( url: "https://github.com/apple/swift-crypto.git", "3.8.0"..<"5.0.0" )
    ],
    targets: [
        .target(
            name: "MIOAWSCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .target(
            name: "MIOAWSS3",
            dependencies: [
                "MIOAWSCore"
            ]
        ),
        .testTarget(
            name: "MIOAWSS3Tests",
            dependencies: ["MIOAWSS3"]
        ),
    ]
)
