// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "apple-fm",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "fm",
            path: ".",
            sources: ["main.swift"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
