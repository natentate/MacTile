// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTile",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacTile", targets: ["MacTile"]),
        .library(name: "MacTileCore", targets: ["MacTileCore"]),
    ],
    targets: [
        // Pure model + geometry. No AppKit, so it is fully unit-testable.
        .target(name: "MacTileCore"),
        // The menu bar app: Accessibility, global hot keys, drag panel, settings UI.
        .executableTarget(
            name: "MacTile",
            dependencies: ["MacTileCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(name: "MacTileCoreTests", dependencies: ["MacTileCore"]),
    ]
)
