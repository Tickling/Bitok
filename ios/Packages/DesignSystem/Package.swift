// swift-tools-version: 5.9
import PackageDescription

/// Дизайн-система «Биток»: оформления Ivory & Oxblood / Midnight Chalk, Liquid Glass, компоненты.
let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
    targets: [.target(name: "DesignSystem")]
)
