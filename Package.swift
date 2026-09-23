// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexPets",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexPets", targets: ["CodexPets"])
    ],
    targets: [
        .executableTarget(
            name: "CodexPets",
            path: "Sources/CodexPets",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CodexPetsTests",
            dependencies: ["CodexPets"],
            path: "Tests/CodexPetsTests"
        )
    ]
)
