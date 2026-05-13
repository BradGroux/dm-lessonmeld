// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "dm-lessonmeld",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DMLessonMeldCore", targets: ["DMLessonMeldCore"]),
        .executable(name: "dmlesson", targets: ["DMLessonMeldCLI"]),
        .executable(name: "DMLessonMeld", targets: ["DMLessonMeld"])
    ],
    targets: [
        .target(name: "DMLessonMeldCore"),
        .executableTarget(
            name: "DMLessonMeldCLI",
            dependencies: ["DMLessonMeldCore"]
        ),
        .executableTarget(
            name: "DMLessonMeld",
            dependencies: ["DMLessonMeldCore"]
        ),
        .testTarget(
            name: "DMLessonMeldCoreTests",
            dependencies: ["DMLessonMeldCore"]
        )
    ]
)
