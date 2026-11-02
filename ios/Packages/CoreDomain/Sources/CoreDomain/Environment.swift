import Foundation

/// Абстракция времени — домен никогда не вызывает `Date()` напрямую (NFR-005.7).
public protocol DateProvider: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    public func now() -> Date { Date() }
}

public protocol IDGenerator: Sendable {
    func make() -> UUID
}

public struct RandomIDGenerator: IDGenerator {
    public init() {}
    public func make() -> UUID { UUID() }
}

/// Флаги функциональности. Клиент получает UI-флаги из `GET /bff/config`;
/// решение «нужна ли оплата» принимает сервер (PaymentPolicy).
public enum FeatureFlag: String, Sendable {
    case paymentsEnabled
    case refundsEnabled
    case shopEnabled
}

public protocol FeatureFlags: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
}

public struct StaticFeatureFlags: FeatureFlags {
    private let enabled: Set<FeatureFlag>
    public init(enabled: Set<FeatureFlag> = []) { self.enabled = enabled }
    public func isEnabled(_ flag: FeatureFlag) -> Bool { enabled.contains(flag) }
}
