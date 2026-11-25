// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "IncomeAllocator",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Income",
            targets: ["Income"]
        ),
        .executable(
            name: "AllocatorMacOS",
            targets: ["AllocatorMacOS"]
        ),
        .executable(
            name: "income",
            targets: ["AllocatorCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/Primitives.git", branch: "master"),
        .package(url: "https://github.com/swift-langs/Parsers.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Arguments.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Terminal.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Clipboard.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "Income",
            dependencies: [
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Parsers", package: "Parsers"),
            ]
        ),
        .executableTarget(
            name: "AllocatorMacOS",
            dependencies: [
                "Income",
                .product(name: "Clipboard", package: "Clipboard"),
            ]
        ),
        .executableTarget(
            name: "AllocatorCLI",
            dependencies: [
                "Income",
                .product(name: "Arguments", package: "Arguments"),
                .product(name: "Terminal", package: "Terminal"),
                .product(name: "Clipboard", package: "Clipboard"),
            ]
        ),
    ]
)

for target in package.targets {
    switch target.type {
    case .regular, .executable, .test, .macro:
        var settings = target.swiftSettings ?? []

        settings.append(
            .treatAllWarnings(as: .error)
        )

        target.swiftSettings = settings

    case .plugin, .system, .binary:
        break

    @unknown default:
        break
    }
}
