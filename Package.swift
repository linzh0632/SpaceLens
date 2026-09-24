// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SpaceLensCore", platforms: [.macOS(.v12)], products: [.library(name: "SpaceLensCore", targets: ["SpaceLensCore"])], targets: [.target(name: "SpaceLensCore", path: "Sources/Core", linkerSettings: [.linkedLibrary("archive"), .linkedLibrary("sqlite3")]), .testTarget(name: "SpaceLensCoreTests", dependencies: ["SpaceLensCore"], path: "Tests/CoreTests")])
