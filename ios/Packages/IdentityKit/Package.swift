// swift-tools-version: 5.9
import PackageDescription

/// Вход по телефону или email (OTP), сессия и токены (FR-001, FR-002).
let package = Package(
    name: "IdentityKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "IdentityDomain", targets: ["IdentityDomain"])],
    dependencies: [.package(path: "../CoreDomain")],
    targets: [.target(name: "IdentityDomain", dependencies: ["CoreDomain"])]
)
