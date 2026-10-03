// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Taggart",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Taggart", targets: ["Taggart"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sbooth/CXXTagLib", from: "2.3.2"),
    ],
    targets: [
        // C++ shim over TagLib exposing a plain C API, so Swift needs no C++ interop.
        .target(
            name: "TagBridge",
            dependencies: [
                .product(name: "taglib", package: "CXXTagLib"),
            ]
        ),
        // UI-free model and tag I/O layer.
        .target(
            name: "TaggartCore",
            dependencies: ["TagBridge"]
        ),
        // The SwiftUI app.
        .executableTarget(
            name: "Taggart",
            dependencies: ["TaggartCore"]
        ),
        .testTarget(
            name: "TaggartCoreTests",
            dependencies: ["TaggartCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
