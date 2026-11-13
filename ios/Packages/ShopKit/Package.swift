// swift-tools-version: 5.9
import PackageDescription

/// ЗАДЕЛ (v1.0): магазин киев. Доменные модели готовы, UI — заглушка «Скоро» (флаг shopEnabled).
let package = Package(
    name: "ShopKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShopDomain", targets: ["ShopDomain"]),
        .library(name: "ShopUI", targets: ["ShopUI"]),
    ],
    dependencies: [
        .package(path: "../CoreDomain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "ShopDomain", dependencies: ["CoreDomain"]),
        .target(name: "ShopUI", dependencies: ["ShopDomain", "DesignSystem"]),
        .testTarget(name: "ShopDomainTests", dependencies: ["ShopDomain", "CoreDomain"]),
    ]
)
