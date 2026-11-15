// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flick",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .systemLibrary(
            name: "CMpv",
            pkgConfig: "mpv",
            providers: [.brew(["mpv"])]
        ),
        .executableTarget(
            name: "Flick",
            dependencies: ["CMpv", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Xcc", "-DGL_SILENCE_DEPRECATION"])],
            linkerSettings: [
                .linkedFramework("OpenGL"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "FlickTests",
            dependencies: ["Flick"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
