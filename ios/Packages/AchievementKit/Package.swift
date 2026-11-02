// swift-tools-version: 5.9
import PackageDescription

/// Достижения, турниры, медали (включая медаль участника), статистика турниров, уникализация профиля.
let package = Package(
    name: "AchievementKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AchievementDomain", targets: ["AchievementDomain"]),
        .library(name: "AchievementUI", targets: ["AchievementUI"]),
    ],
    dependencies: [
        .package(path: "../CoreDomain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "AchievementDomain", dependencies: ["CoreDomain"]),
        .target(name: "AchievementUI", dependencies: ["AchievementDomain", "CoreDomain", "DesignSystem"]),
        .testTarget(name: "AchievementDomainTests", dependencies: ["AchievementDomain", "CoreDomain"]),
    ]
)
