// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ventanas",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (no AppKit, no Accessibility), so it can be checked without permissions.
        .target(name: "VentanasCore", path: "Sources/VentanasCore"),
        .executableTarget(
            name: "Ventanas",
            dependencies: ["VentanasCore"],
            path: "Sources/Ventanas",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // `swift run Checks`: exits with code 1 if any case fails.
        .executableTarget(name: "Checks", dependencies: ["VentanasCore"], path: "Checks/Checks"),
    ]
)
