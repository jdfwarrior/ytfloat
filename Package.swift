// swift-tools-version: 6.0
import PackageDescription

let releaseSettings: [SwiftSetting] = [.unsafeFlags(["-Osize"], .when(configuration: .release))]

let package = Package(
    name: "YTFloat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YTFloat", targets: ["YTFloat"]),
        .executable(name: "ytfloat-cli", targets: ["YTFloatCLI"])
    ],
    targets: [
        .target(name: "YTFloatCore", swiftSettings: releaseSettings),
        .executableTarget(name: "YTFloat", dependencies: ["YTFloatCore"], exclude: ["Resources"], swiftSettings: releaseSettings),
        .executableTarget(name: "YTFloatCLI", dependencies: ["YTFloatCore"], path: "Sources/CLI", swiftSettings: releaseSettings),
        .testTarget(name: "YTFloatCoreTests", dependencies: ["YTFloatCore"])
    ],
    swiftLanguageModes: [.v5]
)
