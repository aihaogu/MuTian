// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeGu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DeGu", targets: ["DeGu"])
    ],
    targets: [
        .executableTarget(
            name: "DeGu",
            path: "DeGu",
            exclude: ["Resources"]
        )
    ]
)
