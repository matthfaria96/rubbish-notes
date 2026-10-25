// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RubbishNotes",
    platforms: [.macOS("15.0")],
    dependencies: [
        // MIT. In-app updates (feed at witchmymac.com/appcast/rubbishnotes.xml).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "RubbishNotes",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/RubbishNotes"
        ),
        // Needs Xcode: the Command Line Tools lack the Swift Testing macros.
        .testTarget(name: "RubbishNotesTests", dependencies: ["RubbishNotes"], path: "Tests/RubbishNotesTests"),
    ]
)
