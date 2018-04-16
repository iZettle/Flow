// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "Flow",
    products: [
        .library(
            name: "Flow",
            targets: ["Flow"]),
    ],
    targets: [
        .target(
            name: "Flow",
            dependencies: [],
            path: "Flow"),
        .testTarget(
            name: "FlowTests",
            dependencies: ["Flow"]),
    ]
)
