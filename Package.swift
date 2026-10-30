// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "STLMedic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "STLMedic", targets: ["STLMedic"])],
    targets: [.executableTarget(name: "STLMedic")]
)
