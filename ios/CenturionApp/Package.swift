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
        
        // Tailscale — WireGuard-based tunnel for remote access
        // When away from home, connects via Tailscale IP
        .package(url: "https://github.com/tailscale/tailscale-client-swift.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "CenturionApp",
            dependencies: [
                .product(name: "Sodium", package: "swift-sodium"),
                .product(name: "TailscaleClient", package: "tailscale-client-swift"),
            ],
            swiftSettings: [
                .unsafeFlags(["-O"])
            ]
        )
    ]
)
