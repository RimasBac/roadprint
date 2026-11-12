// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RoadPrintCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RoadPrintCore", targets: ["RoadPrintCore"])
    ],
    targets: [
        .target(
            name: "RoadPrintCore",
            resources: [.copy("Resources/places.rpgeo"), .copy("Resources/areas.rppl"), .copy("Resources/roads.rpgeo")]
        ),
        .testTarget(
            name: "RoadPrintCoreTests",
            dependencies: ["RoadPrintCore"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
