// swift-tools-version: 5.9
import PackageDescription

/// ЗАДЕЛ (v1.0): экран оплаты СБП. Доменная модель Payment и порт PaymentGateway — в CoreDomain.
let package = Package(
    name: "PaymentKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PaymentUI", targets: ["PaymentUI"])],
    dependencies: [
        .package(path: "../CoreDomain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [.target(name: "PaymentUI", dependencies: ["CoreDomain", "DesignSystem"])]
)
