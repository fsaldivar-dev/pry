// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "pry",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "pry", targets: ["Pry"]),
        .library(name: "PryLib", targets: ["PryLib"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "PryLib",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            path: "Sources/PryLib"
        ),
        .executableTarget(
            name: "Pry",
            dependencies: ["PryLib"],
            path: "Sources/Pry"
        ),
        .testTarget(
            name: "PryLibTests",
            dependencies: ["PryLib"],
            path: "Tests/PryLibTests"
        ),
    ]
)
