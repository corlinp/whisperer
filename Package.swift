// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Voibe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Voibe",
            targets: ["Voibe"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Voibe",
            dependencies: [],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
) 