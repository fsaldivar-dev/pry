// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "pry",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "pry", targets: ["Pry"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
    ],
    targets: [
        .executableTarget(
            name: "Pry",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/Pry"
        ),
    ]
)
