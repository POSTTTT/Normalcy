// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Normalcy",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Normalcy", resources: [.copy("Resources/AppIcon.png")])]
)
