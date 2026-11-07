// BookingKit/Tests/BookingDomainTests/BookingStateMachineTests.swift
import Testing
import Foundation
import CoreDomain
@testable import BookingDomain

@Suite("Booking state machine")
struct BookingStateMachineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let coach = UserID()
    let student = UserID()

    func makeSlot(startsIn hours: Double = 48) throws -> BookingSlot {
        try BookingSlot(id: ID(), trainerId: coach, clubId: ID(),
                        startsAt: now.addingTimeInterval(hours * 3600),
                        durationMinutes: 60, price: .rubles(2500))
    }

    func makeRequest() throws -> Booking {
        try Booking.request(id: ID(), slot: makeSlot(), studentId: student, comment: nil, now: now)
    }

    @Test("paymentsEnabled = false: AWAITING_COACH_APPROVAL → CONFIRMED")
    func approveWithoutPayment() async throws {
        var booking = try makeRequest()
        let decision = await PaymentsDisabledPolicy().decide(for: booking, settings: TrainerBookingSettings())
        try booking.approve(by: .coach(coach), decision: decision, now: now)
        #expect(booking.status == .confirmed)
        #expect(booking.paymentDeadline == nil)
    }

    @Test("paymentsEnabled = true: AWAITING_COACH_APPROVAL → AWAITING_PAYMENT с дедлайном")
    func approveWithPayment() throws {
        var booking = try makeRequest()
        try booking.approve(by: .coach(coach), decision: .required(amount: booking.price, ttl: 900), now: now)
        #expect(booking.status == .awaitingPayment)
        #expect(booking.paymentDeadline == now.addingTimeInterval(900))
        // Холд слота переживает платёжную сессию (race TTL vs оплата)
        #expect(booking.slotHoldDeadline == now.addingTimeInterval(900 + Booking.paymentGracePeriod))
    }

    @Test func paymentSucceededIsIdempotent() throws {
        var booking = try makeRequest()
        try booking.approve(by: .coach(coach), decision: .required(amount: booking.price, ttl: 900), now: now)
        let paymentId = PaymentID()
        try booking.markPaid(paymentId: paymentId, amount: booking.price, now: now)
        try booking.markPaid(paymentId: paymentId, amount: booking.price, now: now) // повторный webhook
        #expect(booking.status == .confirmed)
    }

    @Test func studentCannotApprove() throws {
        var booking = try makeRequest()
        #expect(throws: BookingError.forbidden) {
            try booking.approve(by: .student(student), decision: .notRequired, now: now)
        }
    }

    @Test func expiredCannotBeApproved() throws {
        var booking = try makeRequest()
        try booking.expire(now: now)
        #expect(throws: BookingError.invalidStateTransition(from: .expired, to: .confirmed)) {
            try booking.approve(by: .coach(coach), decision: .notRequired, now: now)
        }
    }

    @Test func coachAssignsTimeToOwnStudent() throws {
        let booking = try Booking.assignByCoach(id: ID(), slot: makeSlot(), studentId: student, coachId: coach,
                                                isCoachesStudent: true, decision: .notRequired, now: now)
        #expect(booking.status == .confirmed)
        #expect(booking.initiatedBy == .coach)
    }

    @Test("Холд слота при переходе к оплате заменяется, а не расширяется")
    func holdIsResetToPaymentDeadline() throws {
        var slot = try makeSlot()
        try slot.hold(until: now.addingTimeInterval(24 * 3600), now: now)
        slot.resetHold(until: now.addingTimeInterval(20 * 60))
        #expect(slot.heldUntil == now.addingTimeInterval(20 * 60))
        #expect(!slot.isBookable(at: now.addingTimeInterval(19 * 60)))
        #expect(slot.isBookable(at: now.addingTimeInterval(21 * 60)))
    }

    @Test func allowedActionsDependOnRole() throws {
        let booking = try makeRequest()
        #expect(booking.allowedActions(for: .coach(coach), now: now) == [.approve, .reject])
        #expect(booking.allowedActions(for: .student(student), now: now) == [.cancel])
        #expect(booking.allowedActions(for: .student(UserID()), now: now).isEmpty)
    }

    @Test func unknownStatusFromServerDoesNotCrash() throws {
        let data = Data(#""SOME_FUTURE_STATUS""#.utf8)
        #expect(try JSONDecoder().decode(BookingStatus.self, from: data) == .unknown)
    }
}
