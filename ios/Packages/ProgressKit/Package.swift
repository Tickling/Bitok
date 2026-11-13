// swift-tools-version: 5.9
import PackageDescription

/// Прогресс игрока: 5 метрик 0–100, EMA, уровни, приватность; экран с радаром и историей.
let package = Package(
    name: "ProgressKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ProgressDomain", targets: ["ProgressDomain"]),
        .library(name: "ProgressUI", targets: ["ProgressUI"]),
    ],
    dependencies: [
        .package(path: "../CoreDomain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "ProgressDomain", dependencies: ["CoreDomain"]),
        .target(name: "ProgressUI", dependencies: ["ProgressDomain", "CoreDomain", "DesignSystem"]),
        .testTarget(name: "ProgressDomainTests", dependencies: ["ProgressDomain", "CoreDomain"]),
    ]
)
