// swift-tools-version: 5.9
import PackageDescription

/// Новости и уроки (FR-018, FR-019).
let package = Package(
    name: "ContentKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ContentDomain", targets: ["ContentDomain"])],
    dependencies: [.package(path: "../CoreDomain")],
    targets: [.target(name: "ContentDomain", dependencies: ["CoreDomain"])]
)
