// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Whisperer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Whisperer",
            targets: ["Whisperer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Whisperer",
            dependencies: [],
            resources: [
                .process("Resources/Assets")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        )
    ]
) 