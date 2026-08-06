// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KingfisherPet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KingfisherPet",
            path: "Sources/KingfisherPet"
        )
    ]
)
