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
        .target(name: "PicseeInfrastructure", dependencies: ["PicseeCore"]),
        .target(name: "PicseeMacUI", dependencies: ["PicseeCore", "PicseeApplication"]),
        .testTarget(name: "PicseeApplicationTests", dependencies: ["PicseeCore", "PicseeApplication"]),
        .testTarget(name: "PicseeMacUITests", dependencies: ["PicseeMacUI"]),
        .testTarget(name: "PicseeCoreTests", dependencies: ["PicseeCore"]),
        .testTarget(name: "PicseeInfrastructureTests", dependencies: ["PicseeCore", "PicseeInfrastructure"]),
    ],
    swiftLanguageModes: [.v6]
)

// Exercise two real Sessions against the real admission actor at the integration seam.
package.targets.first(where: { $0.name == "PicseeInfrastructureTests" })!.dependencies.append("PicseeApplication")

// Preferences implement the Application store port.
package.targets.first(where: { $0.name == "PicseeInfrastructure" })!.dependencies.append("PicseeApplication")
