// swift-tools-version:5.9
// HYDRA-UMC-IOS-CONTROL - the rules of the native iPhone app (server link, sign-in, session, global STOP, languages) in a package with no UIKit or SwiftUI, so they are tested without a phone.
import PackageDescription

let package = Package(
    name: "HydraCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "HydraCore", targets: ["HydraCore"])],
    targets: [
        .target(name: "HydraCore", resources: [.copy("Resources/i18n")]),
        .testTarget(name: "HydraCoreTests", dependencies: ["HydraCore"]),
    ]
)
