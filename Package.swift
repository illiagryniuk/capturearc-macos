// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NotchShelf",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotchShelf", targets: ["NotchShelf"])
    ],
    targets: [
        .executableTarget(
            name: "NotchShelf",
            path: "Sources/NotchShelf"
        ),
        .testTarget(
            name: "NotchShelfTests",
            dependencies: ["NotchShelf"],
            path: "Tests/NotchShelfTests"
        )
    ]
)
