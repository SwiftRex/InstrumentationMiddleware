// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InstrumentationMiddleware",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "InstrumentationMiddleware", targets: ["InstrumentationMiddleware"])
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftRex/SwiftRex.git", from: "0.7.1")
    ],
    targets: [
        .target(
            name: "InstrumentationMiddleware",
            dependencies: [.product(name: "CombineRex", package: "SwiftRex")]
        )
    ]
)
