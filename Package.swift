// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HarmonyEngine",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "HarmonyEngine",
            targets: ["HarmonyEngine"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/cemolcay/MusicTheory.git", from: "2.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "HarmonyEngine",
            dependencies: ["MusicTheory"]
        ),
        .testTarget(
            name: "HarmonyEngineTests",
            dependencies: ["HarmonyEngine"]
        ),
    ],
    swiftLanguageModes: [.v6],
)
