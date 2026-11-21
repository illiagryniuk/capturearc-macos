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
    dependencies: [.package(path: "Packages/ClipboardDemoTransport")],
    targets: [
        .executableTarget(
            name: "NotchShelf",
            dependencies: [.product(name: "ClipboardDemoTransport", package: "ClipboardDemoTransport")],
            path: "Sources/NotchShelf"
        ),
        .testTarget(
            name: "NotchShelfTests",
            dependencies: ["NotchShelf"],
            path: "Tests/NotchShelfTests"
        )
    ]
)
