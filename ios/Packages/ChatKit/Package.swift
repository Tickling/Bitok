// swift-tools-version: 5.9
import PackageDescription

/// Чат тренер ↔ ученик, «Предложить поиграть», «Игроки клуба» (FR-017, FR-030).
let package = Package(
    name: "ChatKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ChatDomain", targets: ["ChatDomain"])],
    dependencies: [.package(path: "../CoreDomain")],
    targets: [
        .target(name: "ChatDomain", dependencies: ["CoreDomain"]),
        .testTarget(name: "ChatDomainTests", dependencies: ["ChatDomain", "CoreDomain"]),
    ]
)
