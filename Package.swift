// swift-tools-version: 6.0
// =============================================================================
// HYDRA-UMC iOS Control - Swift Package manifest
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0 - see LICENSE
//
// Scaffolding only - defines the package structure so VSCode's Swift
// extension (see .vscode/extensions.json) can resolve/index the source
// tree and `swift build` works for local iteration on non-UI logic
// (Networking/, Bluetooth/). A real iOS app target that ships to a
// device/the App Store still needs an actual Xcode project (.xcodeproj)
// wrapping a SwiftUI App target - Swift Package Manager alone does not
// produce an installable iOS .app bundle. Creating that Xcode project is
// intentionally left to the project owner ("la app la voy hacer yo") -
// this manifest exists so the Sources/ tree is buildable/lintable from
// VSCode before that Xcode project exists.
// =============================================================================
import PackageDescription

let package = Package(
    name: "HydraUMCControl",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "HydraUMCControl", targets: ["HydraUMCControl"])
    ],
    targets: [
        .target(
            name: "HydraUMCControl",
            dependencies: [],
            path: "Sources/HydraUMCControl"
        )
    ]
)
