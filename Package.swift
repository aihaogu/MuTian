// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MuTian",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MuTian", targets: ["MuTian"])
    ],
    targets: [
        .executableTarget(
            name: "MuTian",
            path: "MuTian",
            exclude: ["Resources"]
        )
    ]
)
