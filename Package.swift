// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RubbishNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "RubbishNotes", path: "Sources/RubbishNotes")
    ]
)
