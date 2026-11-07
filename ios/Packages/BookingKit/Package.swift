// swift-tools-version: 5.9
import PackageDescription

/// Бронирование: домен (state machine, PaymentPolicy) и UI (календари ученика и тренера).
/// Требует Xcode 16+ (типизированные ошибки `throws(BookingError)`).
let package = Package(
    name: "BookingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BookingDomain", targets: ["BookingDomain"]),
        .library(name: "BookingUI", targets: ["BookingUI"]),
    ],
    dependencies: [
        .package(path: "../CoreDomain"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "BookingDomain", dependencies: ["CoreDomain"]),
        .target(name: "BookingUI", dependencies: ["BookingDomain", "CoreDomain", "DesignSystem"]),
        .testTarget(name: "BookingDomainTests", dependencies: ["BookingDomain", "CoreDomain"]),
    ]
)
