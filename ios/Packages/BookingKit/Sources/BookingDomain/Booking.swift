// BookingKit/Sources/BookingDomain/Booking.swift
import Foundation
import CoreDomain

public enum BookingInitiator: String, Codable, Sendable { case student = "STUDENT", coach = "COACH" }

public struct Booking: Identifiable, Hashable, Codable, Sendable {
    public let id: BookingID
    public let slotId: SlotID
    public let studentId: UserID
    public let trainerId: UserID
    public let initiatedBy: BookingInitiator
    public let startsAt: Date
    public let durationMinutes: Int
    public let price: Money
    public private(set) var status: BookingStatus
    public private(set) var paymentRequired: Bool
    public private(set) var paymentId: PaymentID?
    public private(set) var paymentDeadline: Date?
    public private(set) var draftExpiresAt: Date?
    public var studentComment: String?
    public private(set) var cancellationReason: CancellationReason?
    public private(set) var lateCancellation: Bool
    public let rescheduledFromId: BookingID?
    public private(set) var rescheduleCount: Int
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var version: Int

    public static let draftTTL: TimeInterval = 5 * 60
    public static let approvalTTL: TimeInterval = 24 * 3600
    public static let paymentGracePeriod: TimeInterval = 5 * 60
    public static let maxReschedules = 2

    // MARK: - Factories

    /// Двухшаговый UX: слот удерживается 5 минут, пока ученик заполняет детали.
    public static func reserveDraft(id: BookingID, slot: BookingSlot, studentId: UserID,
                                    now: Date) throws(BookingError) -> Booking {
        var booking = try make(id: id, slot: slot, studentId: studentId, initiatedBy: .student,
                               status: .draft, comment: nil, now: now)
        booking.draftExpiresAt = now.addingTimeInterval(draftTTL)
        return booking
    }

    /// Основной сценарий: заявка сразу уходит тренеру.
    public static func request(id: BookingID, slot: BookingSlot, studentId: UserID,
                               comment: String?, rescheduledFrom: Booking? = nil,
                               now: Date) throws(BookingError) -> Booking {
        try make(id: id, slot: slot, studentId: studentId, initiatedBy: .student,
                 status: .awaitingCoachApproval, comment: comment, rescheduledFrom: rescheduledFrom, now: now)
    }

    /// FR-028: тренер сам назначает время своему ученику; оплата — по той же PaymentPolicy.
    public static func assignByCoach(id: BookingID, slot: BookingSlot, studentId: UserID,
                                     coachId: UserID, isCoachesStudent: Bool,
                                     decision: PaymentDecision, now: Date) throws(BookingError) -> Booking {
        guard coachId == slot.trainerId else { throw BookingError.forbidden }
        guard isCoachesStudent else { throw BookingError.notCoachesStudent }
        var booking = try make(id: id, slot: slot, studentId: studentId, initiatedBy: .coach,
                               status: .awaitingCoachApproval, comment: nil, now: now)
        booking.apply(decision, now: now)
        return booking
    }

    private static func make(id: BookingID, slot: BookingSlot, studentId: UserID,
                             initiatedBy: BookingInitiator, status: BookingStatus, comment: String?,
                             rescheduledFrom: Booking? = nil, now: Date) throws(BookingError) -> Booking {
        guard slot.isBookable(at: now) else { throw BookingError.slotAlreadyTaken }
        return Booking(
            id: id, slotId: slot.id, studentId: studentId, trainerId: slot.trainerId,
            initiatedBy: initiatedBy, startsAt: slot.startsAt, durationMinutes: slot.durationMinutes,
            price: slot.price, status: status, paymentRequired: false, paymentId: nil,
            paymentDeadline: nil, draftExpiresAt: nil, studentComment: comment,
            cancellationReason: nil, lateCancellation: false,
            rescheduledFromId: rescheduledFrom?.id,
            rescheduleCount: (rescheduledFrom?.rescheduleCount ?? -1) + 1,
            createdAt: now, updatedAt: now, version: 0
        )
    }

    // MARK: - Derived

    /// Момент автоматического истечения заявки (BR-005.5).
    public var approvalExpiresAt: Date {
        min(createdAt.addingTimeInterval(Self.approvalTTL), startsAt.addingTimeInterval(-2 * 3600))
    }

    /// До какого момента держать слот: при оплате — дедлайн + grace (защита от race TTL vs оплата).
    public var slotHoldDeadline: Date? {
        switch status {
        case .draft: draftExpiresAt
        case .awaitingCoachApproval: approvalExpiresAt
        case .awaitingPayment: paymentDeadline?.addingTimeInterval(Self.paymentGracePeriod)
        default: nil
        }
    }

    /// Действия, доступные актору (для UI). Сервер возвращает то же в `allowedActions`.
    public func allowedActions(for actor: BookingActor, now: Date) -> Set<BookingAction> {
        let isStudent = actor == .student(studentId)
        let isCoach = actor == .coach(trainerId)
        var actions: Set<BookingAction> = []
        switch status {
        case .draft where isStudent: actions = [.submit, .cancel]
        case .awaitingCoachApproval where isCoach: actions = [.approve, .reject]
        case .awaitingCoachApproval where isStudent: actions = [.cancel]
        case .awaitingPayment where isStudent: actions = [.pay, .cancel]
        case .awaitingPayment where isCoach: actions = [.cancel]
        case .confirmed where isCoach:
            actions = [.cancel, .reschedule]
            if now >= startsAt { actions.formUnion([.complete, .noShow]) }
        case .confirmed where isStudent:
            actions = now < startsAt ? [.cancel, .reschedule] : []
        default: break
        }
        if rescheduleCount >= Self.maxReschedules { actions.remove(.reschedule) }
        return actions
    }

    // MARK: - Transitions

    public mutating func submit(by actor: BookingActor, comment: String?, now: Date) throws(BookingError) {
        guard actor == .student(studentId) else { throw BookingError.forbidden }
        try transition(to: .awaitingCoachApproval, now: now)
        studentComment = comment
        draftExpiresAt = nil
    }

    /// Подтверждение тренером. Целевой статус выбирает PaymentDecision — домен не знает о флагах.
    public mutating func approve(by actor: BookingActor, decision: PaymentDecision, now: Date) throws(BookingError) {
        guard actor == .coach(trainerId) else { throw BookingError.forbidden }
        guard status == .awaitingCoachApproval else {
            throw BookingError.invalidStateTransition(from: status, to: .confirmed)
        }
        apply(decision, now: now)
    }

    public mutating func reject(by actor: BookingActor, reason: CancellationReason?, now: Date) throws(BookingError) {
        guard actor == .coach(trainerId) else { throw BookingError.forbidden }
        guard let reason else { throw BookingError.reasonRequired }
        try transition(to: .rejectedByCoach, now: now)
        cancellationReason = reason
    }

    public mutating func attachPayment(_ paymentId: PaymentID) {
        self.paymentId = paymentId
    }

    /// PaymentSucceeded (только по серверному webhook). Идемпотентно для повторной доставки.
    public mutating func markPaid(paymentId: PaymentID, amount: Money, now: Date) throws(BookingError) {
        if status == .confirmed, self.paymentId == paymentId { return }
        guard self.paymentId == nil || self.paymentId == paymentId, amount == price else {
            throw BookingError.paymentMismatch
        }
        try transition(to: .confirmed, now: now)
        self.paymentId = paymentId
    }

    /// PaymentFailed / PaymentExpired → бронь истекает, слот освобождается.
    public mutating func paymentNotCompleted(now: Date) throws(BookingError) {
        guard status == .awaitingPayment else { return } // повторная доставка события — no-op
        try transition(to: .expired, now: now)
    }

    public mutating func cancel(by actor: BookingActor, reason: CancellationReason?,
                                freeCancellationHours: Int, now: Date) throws(BookingError) {
        switch actor {
        case .student(let id) where id == studentId:
            // «Поздняя отмена» имеет смысл только для уже подтверждённой тренировки (BR-007.1).
            let wasConfirmed = status == .confirmed
            try transition(to: .cancelledByStudent, now: now)
            let hoursLeft = startsAt.timeIntervalSince(now) / 3600
            lateCancellation = wasConfirmed && hoursLeft < Double(freeCancellationHours)
        case .coach(let id) where id == trainerId:
            guard reason != nil else { throw BookingError.reasonRequired }
            try transition(to: .cancelledByCoach, now: now)
        default:
            throw BookingError.forbidden
        }
        cancellationReason = reason
    }

    public mutating func expire(now: Date) throws(BookingError) {
        try transition(to: .expired, now: now)
    }

    public mutating func complete(now: Date) throws(BookingError) {
        guard now >= startsAt else { throw BookingError.invalidStateTransition(from: status, to: .completed) }
        try transition(to: .completed, now: now)
    }

    public mutating func markNoShow(by actor: BookingActor, now: Date) throws(BookingError) {
        guard actor == .coach(trainerId) else { throw BookingError.forbidden }
        guard now >= startsAt.addingTimeInterval(15 * 60) else {
            throw BookingError.invalidStateTransition(from: status, to: .noShow)
        }
        try transition(to: .noShow, now: now)
    }

    public mutating func markRescheduled(now: Date) throws(BookingError) {
        guard rescheduleCount < Self.maxReschedules else { throw BookingError.rescheduleLimitExceeded }
        try transition(to: .rescheduled, now: now)
    }

    // MARK: - Private

    private mutating func apply(_ decision: PaymentDecision, now: Date) {
        switch decision {
        case .notRequired:
            status = .confirmed
            paymentRequired = false
        case .required(_, let ttl):
            status = .awaitingPayment
            paymentRequired = true
            paymentDeadline = now.addingTimeInterval(ttl)
        }
        updatedAt = now
        version += 1
    }

    private mutating func transition(to next: BookingStatus, now: Date) throws(BookingError) {
        guard status.canTransition(to: next) else {
            throw BookingError.invalidStateTransition(from: status, to: next)
        }
        status = next
        updatedAt = now
        version += 1
    }
}
