// swift-tools-version: 6.0
import PackageDescription

import Foundation

// Swift Testing under Command Line Tools only (no Xcode.app):
// The CLT ship Testing.framework + lib_TestingInterop.dylib outside the default search paths and
// do not ship XCTest for macOS. The linker settings below give the test bundle the runtime rpaths
// it needs. They are applied only when the CLT copy exists, and only to the test target.
//
// SwiftPM's auto-generated test runner module does not inherit per-target flags, so with the CLT
// you must also pass the framework path on the command line, or zero tests run (silently):
//
//     swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks
let cltDeveloperDir = "/Library/Developer/CommandLineTools/Library/Developer"
let hasCLTTesting = FileManager.default.fileExists(atPath: "\(cltDeveloperDir)/Frameworks/Testing.framework")
let cltTestingSettings: [SwiftSetting] = hasCLTTesting
    ? [.unsafeFlags(["-F", "\(cltDeveloperDir)/Frameworks"])]
    : []
let cltTestingLinkerSettings: [LinkerSetting] = hasCLTTesting
    ? [.unsafeFlags([
        "-F", "\(cltDeveloperDir)/Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", "\(cltDeveloperDir)/Frameworks",
        "-Xlinker", "-rpath", "-Xlinker", "\(cltDeveloperDir)/usr/lib",
    ])]
    : []

let package = Package(
    name: "LabForge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LabForgeCore", targets: ["LabForgeCore"]),
        .executable(name: "LabForge", targets: ["LabForge"]),
    ],
    targets: [
        .target(name: "LabForgeCore"),
        .executableTarget(name: "LabForge", dependencies: ["LabForgeCore"]),
        .testTarget(
            name: "LabForgeCoreTests",
            dependencies: ["LabForgeCore"],
            swiftSettings: cltTestingSettings,
            linkerSettings: cltTestingLinkerSettings
        ),
    ]
)
