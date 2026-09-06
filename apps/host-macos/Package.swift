// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DisplayOS",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DisplayOS", targets: ["DisplayOS"])],
    targets: [
        .target(
            name: "VirtualDisplayC",
            path: "VirtualDisplayC",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]
        ),
        .executableTarget(name: "DisplayOS", dependencies: ["VirtualDisplayC"], path: "Sources")
    ]
)
