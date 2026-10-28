// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PicseeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PicseeCore", targets: ["PicseeCore"]),
        .library(name: "PicseeApplication", targets: ["PicseeApplication"]),
        .library(name: "PicseeInfrastructure", targets: ["PicseeInfrastructure"]),
        .library(name: "PicseeMacUI", targets: ["PicseeMacUI"]),
    ],
    targets: [
        .target(name: "PicseeCore"),
        .target(name: "PicseeApplication", dependencies: ["PicseeCore"]),
        .target(name: "PicseeInfrastructure", dependencies: ["PicseeCore"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "PicseeMacUI", dependencies: ["PicseeCore", "PicseeApplication"], exclude: ["B4Samples/PROVENANCE.md"], resources: [
            .copy("B4Samples/alley.jpg"), .copy("B4Samples/lakeside.jpg"),
            .copy("B4Samples/temple.jpg"), .copy("B4Samples/hillside.jpg"),
            .copy("B4Samples/lakehouse.jpg"), .copy("B4Samples/gate.jpg")
        ]),
        .testTarget(name: "PicseeApplicationTests", dependencies: ["PicseeCore", "PicseeApplication"]),
        .testTarget(name: "PicseeMacUITests", dependencies: ["PicseeMacUI", "PicseeInfrastructure"], exclude: ["B4PinnedDesign"]),
        .testTarget(name: "PicseeCoreTests", dependencies: ["PicseeCore"]),
        .testTarget(name: "PicseeInfrastructureTests", dependencies: ["PicseeCore", "PicseeInfrastructure"]),
    ],
    swiftLanguageModes: [.v6]
)

// Exercise two real Sessions against the real admission actor at the integration seam.
package.targets.first(where: { $0.name == "PicseeInfrastructureTests" })!.dependencies.append("PicseeApplication")

// Preferences implement the Application store port.
package.targets.first(where: { $0.name == "PicseeInfrastructure" })!.dependencies.append("PicseeApplication")
