// BookingKit/Sources/BookingDomain/UseCases.swift
import Foundation
import CoreDomain
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol CreateBookingUseCase: Sendable {
    func execute(slotId: SlotID, comment: String?, idempotencyKey: UUID) async throws -> Booking
}

public protocol GetTrainerSlotsUseCase: Sendable {
    func execute(trainerId: UserID, period: DateInterval) async throws -> [BookingSlot]
}

/// Клиентская реализация: быстрый локальный фидбек, переиспользование ключа идемпотентности
/// на все повторы. Финальная проверка инвариантов — на сервере.
public struct CreateBookingInteractor: CreateBookingUseCase {
    private let bookings: BookingRepository
    private let slots: SlotRepository
    private let dates: DateProvider

    public init(bookings: BookingRepository, slots: SlotRepository, dates: DateProvider = SystemDateProvider()) {
        self.bookings = bookings
        self.slots = slots
        self.dates = dates
    }

    public func execute(slotId: SlotID, comment: String?, idempotencyKey: UUID) async throws -> Booking {
        let slot = try await slots.slot(id: slotId)
        guard slot.isBookable(at: dates.now()) else { throw BookingError.slotAlreadyTaken }
        let bookings = self.bookings
        return try await withRetry(maxAttempts: 3) {
            // Один и тот же ключ на все попытки — сервер вернёт уже созданное бронирование.
            try await bookings.create(slotId: slotId, comment: comment, idempotencyKey: idempotencyKey)
        }
    }
}

public struct GetTrainerSlotsInteractor: GetTrainerSlotsUseCase {
    private let slots: SlotRepository

    public init(slots: SlotRepository) { self.slots = slots }

    public func execute(trainerId: UserID, period: DateInterval) async throws -> [BookingSlot] {
        try await slots.slots(trainerId: trainerId, in: period).sorted { $0.startsAt < $1.startsAt }
    }
}

/// Повтор только для транспортных ошибок (таймаут, обрыв). Бизнес-ошибки (409/422) не повторяются.
func withRetry<T: Sendable>(maxAttempts: Int, _ operation: @Sendable () async throws -> T) async throws -> T {
    var attempt = 0
    while true {
        do {
            return try await operation()
        } catch let error as URLError where attempt < maxAttempts - 1 && error.isTransient {
            attempt += 1
            let delay = UInt64(pow(2, Double(attempt)) * 200_000_000) // 0.4 c, 0.8 c …
            try await Task.sleep(nanoseconds: delay + UInt64.random(in: 0...100_000_000))
        }
    }
}

extension URLError {
    var isTransient: Bool {
        [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost].contains(code)
    }
}
