// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "3Fingers",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "3Fingers", targets: ["ThreeFingers"])
    ],
    targets: [
        // C declarations for the private MultitouchSupport.framework types.
        // The framework itself is loaded at runtime with dlopen (see Multitouch.swift).
        .target(name: "CMultitouch"),
        .executableTarget(
            name: "ThreeFingers",
            dependencies: ["CMultitouch"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
