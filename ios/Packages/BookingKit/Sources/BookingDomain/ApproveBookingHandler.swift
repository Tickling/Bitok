// BookingKit/Sources/BookingDomain/ApproveBookingHandler.swift
import Foundation
import CoreDomain

public struct ApproveBookingHandler: Sendable {
    public init(bookings: BookingStore, settings: TrainerSettingsStore, policy: PaymentPolicy,
                payments: PaymentGateway, dates: DateProvider) {
        self.bookings = bookings
        self.settings = settings
        self.policy = policy
        self.payments = payments
        self.dates = dates
    }

    let bookings: BookingStore          // порт хранилища (сервер: PostgreSQL; тесты: in-memory)
    let settings: TrainerSettingsStore
    let policy: PaymentPolicy           // PaymentsDisabledPolicy (MVP) | FeatureFlagPaymentPolicy (v1.0)
    let payments: PaymentGateway        // NoopPaymentGateway (MVP) | реальный адаптер (v1.0)
    let dates: DateProvider

    public func handle(bookingId: BookingID, coach: UserID) async throws -> Booking {
        var booking = try await bookings.load(bookingId)
        let trainerSettings = try await settings.load(booking.trainerId)
        let decision = await policy.decide(for: booking, settings: trainerSettings)
        try booking.approve(by: .coach(coach), decision: decision, now: dates.now())
        if case .required(let amount, _) = decision, let deadline = booking.paymentDeadline {
            // В проде вызов идёт асинхронно по событию BookingConfirmedByCoach (Saga, 4.3.6);
            // синхронный вариант показан для наглядности порта.
            let session = try await payments.createSession(
                PaymentSessionRequest(bookingId: booking.id, payerId: booking.studentId,
                                      amount: amount, expiresAt: deadline))
            booking.attachPayment(session.paymentId)
        }
        try await bookings.save(booking, expectedVersion: booking.version - 1)
        return booking
    }
}
