// ⚠️ ЗАДЕЛ (v1.0): используется только при включённом `paymentsEnabled` на сервере.
import Foundation

public enum PaymentStatus: String, Codable, Sendable {
    case created = "CREATED"
    case pending = "PENDING"               // QR / ссылка выданы, ждём оплату
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case expired = "EXPIRED"
    case refundPending = "REFUND_PENDING"
    case partiallyRefunded = "PARTIALLY_REFUNDED"
    case refunded = "REFUNDED"

    public var isFinal: Bool { [.failed, .expired, .refunded].contains(self) }
    public var isPaid: Bool { [.succeeded, .refundPending, .partiallyRefunded].contains(self) }
}

public enum PaymentMethod: String, Codable, Sendable { case sbp = "SBP" }

public enum PaymentError: Error, Equatable, Sendable {
    case invalidTransition(from: PaymentStatus, to: PaymentStatus)
    case refundExceedsAmount
    case amountMismatch
}

/// Платёж. В СБП нет холдирования: деньги списываются сразу, компенсация — только возврат.
public struct Payment: Identifiable, Hashable, Codable, Sendable {
    public let id: PaymentID
    public let bookingId: BookingID?
    public let payerId: UserID
    public let amount: Money
    public let method: PaymentMethod
    public private(set) var status: PaymentStatus
    public private(set) var paymentURL: URL?
    public private(set) var qrPayload: String?
    public let expiresAt: Date
    public private(set) var refundedAmount: Money
    public let createdAt: Date

    public init(id: PaymentID, bookingId: BookingID?, payerId: UserID, amount: Money,
                expiresAt: Date, createdAt: Date) {
        self.id = id
        self.bookingId = bookingId
        self.payerId = payerId
        self.amount = amount
        self.method = .sbp
        self.status = .created
        self.expiresAt = expiresAt
        self.refundedAmount = .zero
        self.createdAt = createdAt
    }

    public mutating func issue(paymentURL: URL, qrPayload: String) throws {
        guard status == .created else { throw PaymentError.invalidTransition(from: status, to: .pending) }
        self.paymentURL = paymentURL
        self.qrPayload = qrPayload
        status = .pending
    }

    /// Идемпотентно: повторное подтверждение успешного платежа — no-op (повторный webhook).
    public mutating func markSucceeded(paidAmount: Money) throws {
        if status == .succeeded { return }
        guard paidAmount == amount else { throw PaymentError.amountMismatch }
        // Оплата после истечения допускается: деньги уже списаны — дальше решает saga (возврат или подтверждение).
        guard status == .pending || status == .expired else {
            throw PaymentError.invalidTransition(from: status, to: .succeeded)
        }
        status = .succeeded
    }

    public mutating func markFailed() throws {
        guard status == .pending || status == .created else {
            throw PaymentError.invalidTransition(from: status, to: .failed)
        }
        status = .failed
    }

    public mutating func expire(now: Date) {
        guard status == .pending || status == .created, now >= expiresAt else { return }
        status = .expired
    }

    public mutating func requestRefund(_ refund: Money) throws {
        guard status.isPaid else { throw PaymentError.invalidTransition(from: status, to: .refundPending) }
        guard refundedAmount.amountMinor + refund.amountMinor <= amount.amountMinor else {
            throw PaymentError.refundExceedsAmount
        }
        status = .refundPending
    }

    public mutating func completeRefund(_ refund: Money) {
        refundedAmount = Money(amountMinor: refundedAmount.amountMinor + refund.amountMinor)
        status = refundedAmount == amount ? .refunded : .partiallyRefunded
    }
}

// MARK: - Порт платёжного контура (Ports & Adapters, ADR-008)

/// Ядро бронирования зависит ТОЛЬКО от этого протокола.
/// MVP: `NoopPaymentGateway`; v1.0: `BFFPaymentGateway` (iOS) / gRPC-адаптер (сервер).
public protocol PaymentGateway: Sendable {
    func createSession(_ request: PaymentSessionRequest) async throws -> PaymentSession
    func status(of paymentId: PaymentID) async throws -> PaymentStatus
    func statusUpdates(of paymentId: PaymentID) -> AsyncThrowingStream<PaymentStatus, Error>
    func cancelSession(_ paymentId: PaymentID) async throws
    func requestRefund(_ paymentId: PaymentID, amount: Money, reason: RefundReason) async throws
}

public struct PaymentSessionRequest: Hashable, Sendable {
    public let bookingId: BookingID
    public let payerId: UserID
    public let amount: Money
    public let expiresAt: Date

    public init(bookingId: BookingID, payerId: UserID, amount: Money, expiresAt: Date) {
        self.bookingId = bookingId
        self.payerId = payerId
        self.amount = amount
        self.expiresAt = expiresAt
    }
}

/// Платёжная сессия СБП: QR (другое устройство) или ссылка в банк (то же устройство).
public struct PaymentSession: Hashable, Codable, Sendable {
    public let paymentId: PaymentID
    public let paymentURL: URL          // https://qr.nspk.ru/... — выбор банка / СБПэй
    public let qrPayload: String
    public let expiresAt: Date

    public init(paymentId: PaymentID, paymentURL: URL, qrPayload: String, expiresAt: Date) {
        self.paymentId = paymentId
        self.paymentURL = paymentURL
        self.qrPayload = qrPayload
        self.expiresAt = expiresAt
    }
}

public enum RefundReason: String, Codable, Sendable {
    case coachCancelled = "COACH_CANCELLED"
    case studentCancelled = "STUDENT_CANCELLED"
    case slotUnavailable = "SLOT_UNAVAILABLE"
    case other = "OTHER"
}

public enum PaymentGatewayError: Error, Equatable, Sendable { case featureDisabled }

/// Адаптер MVP: оплата выключена. Подключение СБП = замена адаптера в composition root.
public struct NoopPaymentGateway: PaymentGateway {
    public init() {}

    public func createSession(_ request: PaymentSessionRequest) async throws -> PaymentSession {
        throw PaymentGatewayError.featureDisabled
    }

    public func status(of paymentId: PaymentID) async throws -> PaymentStatus {
        throw PaymentGatewayError.featureDisabled
    }

    public func statusUpdates(of paymentId: PaymentID) -> AsyncThrowingStream<PaymentStatus, Error> {
        AsyncThrowingStream { $0.finish(throwing: PaymentGatewayError.featureDisabled) }
    }

    public func cancelSession(_ paymentId: PaymentID) async throws {}

    public func requestRefund(_ paymentId: PaymentID, amount: Money, reason: RefundReason) async throws {
        throw PaymentGatewayError.featureDisabled
    }
}
