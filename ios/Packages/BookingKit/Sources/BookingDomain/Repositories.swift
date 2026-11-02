// BookingKit/Sources/BookingDomain/Repositories.swift
import Foundation
import CoreDomain

public struct TrainerFilter: Hashable, Sendable {
    public var clubId: ClubID?
    public var discipline: Discipline?
    public var maxPrice: Money?
    public var availableFrom: Date?
    public var query: String?

    public init(clubId: ClubID? = nil, discipline: Discipline? = nil, maxPrice: Money? = nil,
                availableFrom: Date? = nil, query: String? = nil) {
        self.clubId = clubId
        self.discipline = discipline
        self.maxPrice = maxPrice
        self.availableFrom = availableFrom
        self.query = query
    }
}

public enum BookingHistoryScope: String, Sendable { case upcoming, past, all }

public protocol TrainerRepository: Sendable {
    func trainers(filter: TrainerFilter, cursor: String?, limit: Int) async throws -> Page<Trainer>
    func trainer(id: UserID) async throws -> Trainer
}

public protocol SlotRepository: Sendable {
    func slots(trainerId: UserID, in interval: DateInterval) async throws -> [BookingSlot]
    func slot(id: SlotID) async throws -> BookingSlot
}

public protocol BookingRepository: Sendable {
    /// Повтор с тем же ключом возвращает уже созданное бронирование (Idempotency-Key).
    func create(slotId: SlotID, comment: String?, idempotencyKey: UUID) async throws -> Booking
    func booking(id: BookingID) async throws -> Booking
    func changeStatus(id: BookingID, action: BookingAction, reason: CancellationReason?,
                      expectedVersion: Int) async throws -> Booking
    func history(studentId: UserID, scope: BookingHistoryScope, cursor: String?,
                 limit: Int) async throws -> Page<Booking>
    /// Поток изменений (WebSocket / silent push) для обновления UI в реальном времени.
    func updates(for bookingId: BookingID) -> AsyncStream<Booking>
}

/// Порты хранилища для application-слоя (сервер на Vapor / in-memory в тестах).
public protocol BookingStore: Sendable {
    func load(_ id: BookingID) async throws -> Booking
    /// Оптимистичная блокировка: сохранение падает с `BookingError.versionConflict`, если версия изменилась.
    func save(_ booking: Booking, expectedVersion: Int) async throws
}

public protocol TrainerSettingsStore: Sendable {
    func load(_ trainerId: UserID) async throws -> TrainerBookingSettings
}

/// Системный календарь iOS (EventKit) — порт для FR-010.
public protocol CalendarSyncing: Sendable {
    func upsertEvent(for booking: Booking, trainerName: String, clubAddress: String) async throws
    func removeEvent(for bookingId: BookingID) async throws
}

/// Локальные напоминания (UNUserNotificationCenter) — порт для FR-009 (BR-009.6).
public protocol ReminderScheduling: Sendable {
    func schedule(for booking: Booking, minutesBefore: Int) async throws
    func cancel(for bookingId: BookingID) async
}
