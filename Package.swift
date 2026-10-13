// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [.library(name: "ParcelCore", targets: ["ParcelCore"]), .executable(name: "ParcelCheck", targets: ["ParcelCheck"])]
var targets: [Target] = [
    .target(name: "ParcelCore", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]),
    .executableTarget(name: "ParcelCheck", dependencies: ["ParcelCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")]),
    .testTarget(name: "ParcelCoreTests", dependencies: ["ParcelCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")])
]
#if os(macOS)
products.append(.executable(name: "Parcel", targets: ["ParcelApp"]))
targets.append(.executableTarget(name: "ParcelApp", dependencies: ["ParcelCore"], resources: [.process("Resources")]))
#endif
let package = Package(name: "Parcel", platforms: [.macOS(.v14)], products: products,
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: targets, swiftLanguageVersions: [.v5])
