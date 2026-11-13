// BookingKit/Sources/BookingDomain/PaymentPolicy.swift
import Foundation
import CoreDomain

public enum PaymentDecision: Hashable, Sendable {
    case notRequired
    case required(amount: Money, ttl: TimeInterval)
}

public protocol PaymentPolicy: Sendable {
    func decide(for booking: Booking, settings: TrainerBookingSettings) async -> PaymentDecision
}

/// MVP: оплата выключена — маршрут AWAITING_COACH_APPROVAL → CONFIRMED.
public struct PaymentsDisabledPolicy: PaymentPolicy {
    public init() {}
    public func decide(for booking: Booking, settings: TrainerBookingSettings) async -> PaymentDecision { .notRequired }
}

/// v1.0: флаг `paymentsEnabled` + настройка предоплаты тренера.
public struct FeatureFlagPaymentPolicy: PaymentPolicy {
    private let flags: FeatureFlags
    public static let paymentTTL: TimeInterval = 15 * 60

    public init(flags: FeatureFlags) { self.flags = flags }

    public func decide(for booking: Booking, settings: TrainerBookingSettings) async -> PaymentDecision {
        guard flags.isEnabled(.paymentsEnabled),
              settings.requiresPrepayment,
              booking.price > .zero else { return .notRequired }
        return .required(amount: booking.price, ttl: Self.paymentTTL)
    }
}
