// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftPythonSubprocessExperiment",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SwiftPythonSubprocessExperiment",
            targets: ["SwiftPythonSubprocessExperiment"]
        )
    ],
    targets: [
        .executableTarget(
            name: "SwiftPythonSubprocessExperiment"
        )
    ]
)

