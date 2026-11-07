import Foundation

/// Типобезопасный идентификатор: `ID<User>` нельзя случайно передать вместо `ID<Club>`.
public struct ID<Entity>: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString.lowercased() }
}

/// Маркеры для ссылок между контекстами. Сами агрегаты живут в своих пакетах (BookingKit, AchievementKit),
/// а CoreDomain знает только их идентификаторы — так не возникает циклических зависимостей между пакетами.
public enum BookingTag {}
public enum BookingSlotTag {}
public enum TournamentTag {}

public typealias UserID = ID<User>
public typealias ClubID = ID<Club>
public typealias BookingID = ID<BookingTag>
public typealias SlotID = ID<BookingSlotTag>
public typealias TournamentID = ID<TournamentTag>
public typealias PaymentID = ID<Payment>

/// Курсорная страница (контракт API, раздел 6.1).
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    public let nextCursor: String?

    public init(items: [Item], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
