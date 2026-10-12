// swift-tools-version:5.7
import PackageDescription

// Pure-Swift logic for TempScout (colour maths, calibration, ND calculator, sun maths).
// No UIKit/AVFoundation here, so it is easy to unit test: `swift test` in this folder, or Cmd-U in Xcode.
let package = Package(
    name: "TempScoutCore",
    platforms: [.iOS(.v16), .macOS(.v12)],
    products: [
        .library(name: "TempScoutCore", targets: ["TempScoutCore"])
    ],
    targets: [
        .target(name: "TempScoutCore"),
        .testTarget(name: "TempScoutCoreTests", dependencies: ["TempScoutCore"])
    ]
)
