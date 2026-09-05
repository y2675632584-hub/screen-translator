// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenTranslator",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "ScreenTranslator", targets: ["ScreenTranslator"])],
    targets: [
        .executableTarget(name: "ScreenTranslator"),
        .testTarget(name: "ScreenTranslatorTests", dependencies: ["ScreenTranslator"])
    ],
    swiftLanguageModes: [.v5]
)
