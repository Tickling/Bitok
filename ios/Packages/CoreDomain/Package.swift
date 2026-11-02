// swift-tools-version: 5.9
import PackageDescription

/// Общие типы и порты: ID, Money, пользователи, платёж и порт PaymentGateway, feature flags.
let package = Package(
    name: "CoreDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CoreDomain", targets: ["CoreDomain"])],
    targets: [
        .target(name: "CoreDomain"),
        .testTarget(name: "CoreDomainTests", dependencies: ["CoreDomain"]),
    ]
)
