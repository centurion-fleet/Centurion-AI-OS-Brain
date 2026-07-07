// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CenturionApp",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        // libsodium — cryptographic core for the secure channel
        // X25519 ECDH + XSalsa20-Poly1305 authenticated encryption
        .package(url: "https://github.com/jedisct1/swift-sodium.git", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "CenturionApp",
            dependencies: [
                .product(name: "Sodium", package: "swift-sodium"),
            ],
            swiftSettings: [
                .unsafeFlags(["-O"])
            ]
        )
    ]
)
