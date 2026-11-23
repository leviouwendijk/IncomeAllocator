// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "IncomeTests",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "t_income",
            targets: ["IncomeTestFlows"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/TestFlows.git", branch: "master"),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "IncomeTestFlows",
            dependencies: [
                .product(name: "Income", package: "IncomeAllocator"),
                .product(name: "TestFlows", package: "TestFlows"),
            ]
        ),
    ]
)
