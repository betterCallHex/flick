// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v15)],
    targets: [
        .systemLibrary(
            name: "CMpv",
            pkgConfig: "mpv",
            providers: [.brew(["mpv"])]
        ),
        .executableTarget(
            name: "Flick",
            dependencies: ["CMpv"],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Xcc", "-DGL_SILENCE_DEPRECATION"])],
            linkerSettings: [.linkedFramework("OpenGL")]
        ),
        .testTarget(
            name: "FlickTests",
            dependencies: ["Flick"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
