// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ClipboardDemoTransport",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "ClipboardDemoTransport", targets: ["ClipboardDemoTransport"])],
    targets: [.target(name: "ClipboardDemoTransport", resources: [.process("Resources")]),
              .testTarget(name: "ClipboardDemoTransportTests", dependencies: ["ClipboardDemoTransport"])])
