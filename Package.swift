// swift-tools-version:4.2

import PackageDescription

let package = Package(
    name: "Flow",
    products: [
        .library(
            name: "Flow",
            type: .dynamic,
            targets: ["Flow"]),
    ],
    targets: [
        .target(
            name: "Flow",
            dependencies: [],
            path: "Flow"),
        .testTarget(
            name: "FlowTests",
            dependencies: ["Flow"],
            path: "FlowTests"),
    ]
)
