// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription



let package = Package(
    name: "MIOServerKitAWS_S3",
    platforms: [
       .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "MIOServerKitAWS_S3",
            targets: ["MIOServerKitAWS_S3"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/miolabs/MIOCore.git", .branch("master")),
        .package(url: "https://github.com/miolabs/MIOServerKit.git", .branch("master")),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "MIOServerKitAWS_S3",
            dependencies: ["MIOServerKit", "Crypto", "MIOCore"]),
        .testTarget(
            name: "MIOServerKitAWS_S3Tests",
            dependencies: ["MIOServerKitAWS_S3"]),
    ]
)
