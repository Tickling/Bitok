// swift-tools-version: 5.9
import PackageDescription

/// HTTP-клиент к BFF: авторизация, Idempotency-Key, If-Match, RFC 7807, X-App-Version.
let package = Package(
    name: "CoreNetwork",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CoreNetwork", targets: ["CoreNetwork"])],
    targets: [
        .target(name: "CoreNetwork"),
        .testTarget(name: "CoreNetworkTests", dependencies: ["CoreNetwork"]),
    ]
)
