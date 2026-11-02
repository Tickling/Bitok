// swift-tools-version: 5.9
import PackageDescription

/// Офлайн-кэш последних данных (NFR-004.6): расписание, прогресс, история.
let package = Package(
    name: "CorePersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CorePersistence", targets: ["CorePersistence"])],
    targets: [.target(name: "CorePersistence")]
)
