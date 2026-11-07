import Foundation

/// Деньги в минимальных единицах (копейках), чтобы избежать ошибок округления Double.
public struct Money: Hashable, Codable, Sendable, Comparable {
    public let amountMinor: Int64
    public let currency: Currency

    public enum Currency: String, Codable, Sendable { case rub = "RUB" }

    public init(amountMinor: Int64, currency: Currency = .rub) {
        precondition(amountMinor >= 0, "Money cannot be negative")
        self.amountMinor = amountMinor
        self.currency = currency
    }

    public static func rubles(_ value: Int64) -> Money { Money(amountMinor: value * 100) }
    public static let zero = Money(amountMinor: 0)

    public var decimalValue: Decimal { Decimal(amountMinor) / 100 }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency)
        return lhs.amountMinor < rhs.amountMinor
    }

    /// Процент от суммы с округлением вниз до копейки (частичные возвраты).
    public func percentage(_ percent: Int) -> Money {
        precondition((0...100).contains(percent))
        return Money(amountMinor: amountMinor * Int64(percent) / 100, currency: currency)
    }
}
