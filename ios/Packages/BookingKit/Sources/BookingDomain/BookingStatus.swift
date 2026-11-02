// BookingKit/Sources/BookingDomain/BookingStatus.swift
import Foundation
import CoreDomain

public enum BookingStatus: String, Codable, Sendable, CaseIterable {
    case draft = "DRAFT"
    case awaitingCoachApproval = "AWAITING_COACH_APPROVAL"
    case awaitingPayment = "AWAITING_PAYMENT"
    case confirmed = "CONFIRMED"
    case completed = "COMPLETED"
    case rejectedByCoach = "REJECTED_BY_COACH"
    case cancelledByStudent = "CANCELLED_BY_STUDENT"
    case cancelledByCoach = "CANCELLED_BY_COACH"
    case expired = "EXPIRED"
    case rescheduled = "RESCHEDULED"
    case noShow = "NO_SHOW"
    /// Forward compatibility: новый статус с сервера не роняет старый клиент (см. 9.2 «Версионирование API»).
    case unknown = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BookingStatus(rawValue: raw) ?? .unknown
    }

    /// Статусы, удерживающие слот (уникальный частичный индекс BR-005.1).
    public var holdsSlot: Bool {
        switch self {
        case .draft, .awaitingCoachApproval, .awaitingPayment, .confirmed: true
        default: false
        }
    }

    public var isTerminal: Bool { allowedTransitions.isEmpty }

    /// Декларативная таблица переходов (зеркало раздела 4.4). Расширение модели = новая строка.
    public var allowedTransitions: Set<BookingStatus> {
        switch self {
        case .draft: [.awaitingCoachApproval, .expired, .cancelledByStudent]
        case .awaitingCoachApproval: [.confirmed, .awaitingPayment, .rejectedByCoach, .cancelledByStudent, .expired]
        case .awaitingPayment: [.confirmed, .expired, .cancelledByStudent, .cancelledByCoach]
        case .confirmed: [.completed, .cancelledByStudent, .cancelledByCoach, .rescheduled, .noShow]
        case .completed, .rejectedByCoach, .cancelledByStudent, .cancelledByCoach,
             .expired, .rescheduled, .noShow, .unknown: []
        }
    }

    public func canTransition(to next: BookingStatus) -> Bool { allowedTransitions.contains(next) }
}

public enum BookingActor: Hashable, Sendable {
    case student(UserID)
    case coach(UserID)
    case system
}

public enum BookingAction: String, Codable, Sendable, CaseIterable {
    case submit = "SUBMIT", approve = "APPROVE", reject = "REJECT", cancel = "CANCEL"
    case pay = "PAY", complete = "COMPLETE", noShow = "NO_SHOW", reschedule = "RESCHEDULE"
}

public enum CancellationReasonCode: String, Codable, Sendable {
    case illness = "ILLNESS"
    case scheduleConflict = "SCHEDULE_CONFLICT"
    case coachUnavailable = "COACH_UNAVAILABLE"
    case clubClosed = "CLUB_CLOSED"
    case other = "OTHER"
}

public struct CancellationReason: Hashable, Codable, Sendable {
    public var code: CancellationReasonCode
    public var text: String?

    public init(code: CancellationReasonCode, text: String? = nil) {
        self.code = code
        self.text = text.map { String($0.prefix(200)) }
    }
}
