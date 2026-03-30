// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VoiceInput",
            targets: ["VoiceInput"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            dependencies: []
        )
    ]
)
