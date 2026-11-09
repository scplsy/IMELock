// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IMELockCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "IMELockCore", targets: ["IMELockCore"])],
    targets: [
        .target(name: "IMELockCore", path: "IMELock/Core"),
        .testTarget(name: "IMELockCoreTests", dependencies: ["IMELockCore"], path: "Tests")
    ]
)
