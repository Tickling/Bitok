// BookingKit/Sources/BookingDomain/BookingSlot.swift
import Foundation
import CoreDomain

public enum SlotStatus: String, Codable, Sendable {
    case available = "AVAILABLE", held = "HELD", booked = "BOOKED", blocked = "BLOCKED", cancelled = "CANCELLED"
}

public enum SlotType: String, Codable, Sendable { case individual = "INDIVIDUAL", group = "GROUP" }

public struct BookingSlot: Identifiable, Hashable, Codable, Sendable {
    public let id: SlotID
    public let trainerId: UserID
    public let clubId: ClubID
    public var tableNumber: Int?
    public let startsAt: Date
    public let durationMinutes: Int
    public var price: Money
    public var type: SlotType
    public var capacity: Int
    public private(set) var status: SlotStatus
    public private(set) var heldUntil: Date?
    public private(set) var version: Int

    public init(id: SlotID, trainerId: UserID, clubId: ClubID, tableNumber: Int? = nil,
                startsAt: Date, durationMinutes: Int, price: Money, type: SlotType = .individual,
                capacity: Int = 1, status: SlotStatus = .available, heldUntil: Date? = nil,
                version: Int = 0) throws(DomainValidationError) {
        guard (30...180).contains(durationMinutes), durationMinutes % 15 == 0 else {
            throw DomainValidationError.invalidDuration
        }
        self.id = id
        self.trainerId = trainerId
        self.clubId = clubId
        self.tableNumber = tableNumber
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.price = price
        self.type = type
        self.capacity = type == .individual ? 1 : max(1, capacity)
        self.status = status
        self.heldUntil = heldUntil
        self.version = version
    }

    public var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    public var interval: DateInterval { DateInterval(start: startsAt, end: endsAt) }

    /// Слот доступен, если он свободен или его холд истёк (ленивое истечение — не ждём планировщик).
    public func isBookable(at now: Date) -> Bool {
        switch status {
        case .available: true
        case .held: (heldUntil ?? .distantPast) <= now
        default: false
        }
    }

    public mutating func hold(until deadline: Date, now: Date) throws(BookingError) {
        guard isBookable(at: now) else { throw BookingError.slotAlreadyTaken }
        status = .held
        heldUntil = deadline
        version += 1
    }

    /// Переустановить срок холда при смене этапа брони (заявка → оплата): срок ЗАМЕНЯЕТСЯ, а не расширяется.
    /// При оплате это paymentDeadline + grace — холд переживает платёжную сессию (BR-020.1),
    /// но неоплаченный слот не блокируется на сутки (ошибку поймал тест backend Booking Service).
    public mutating func resetHold(until deadline: Date) {
        guard status == .held else { return }
        heldUntil = deadline
        version += 1
    }

    public mutating func markBooked() {
        status = .booked
        heldUntil = nil
        version += 1
    }

    public mutating func release() {
        guard status == .held || status == .booked else { return }
        status = .available
        heldUntil = nil
        version += 1
    }
}
