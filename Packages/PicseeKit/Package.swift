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
        .testTarget(name: "PicseeCoreTests", dependencies: ["PicseeCore"]),
        .testTarget(name: "PicseeInfrastructureTests", dependencies: ["PicseeCore", "PicseeInfrastructure"]),
    ],
    swiftLanguageModes: [.v6]
)
