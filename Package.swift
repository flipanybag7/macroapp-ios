// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacroApp",
    platforms: [
        .iOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "MacroApp",
            path: "MacroApp"
        )
    ]
)
