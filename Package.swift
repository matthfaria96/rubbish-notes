// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RubbishNotes",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "RubbishNotes", path: "Sources/RubbishNotes"),
        // Needs Xcode: the Command Line Tools lack the Swift Testing macros.
        .testTarget(name: "RubbishNotesTests", dependencies: ["RubbishNotes"], path: "Tests/RubbishNotesTests"),
    ]
)
