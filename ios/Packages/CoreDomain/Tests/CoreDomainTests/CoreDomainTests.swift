import Foundation
import Testing
@testable import CoreDomain

@Suite("Money")
struct MoneyTests {
    @Test func rublesAreStoredInKopecks() {
        #expect(Money.rubles(2500).amountMinor == 250_000)
    }

    @Test func percentageRoundsDown() {
        #expect(Money(amountMinor: 999).percentage(50).amountMinor == 499)
    }
}

@Suite("PhoneNumber")
struct PhoneNumberTests {
    @Test(arguments: ["89991234567", "+7 (999) 123-45-67", "9991234567"])
    func normalizesToE164(raw: String) throws {
        #expect(try PhoneNumber(raw).e164 == "+79991234567")
    }

    @Test func masksForLogs() throws {
        #expect(try PhoneNumber("+79991234567").masked == "+7 *** ***-45-67")
    }

    @Test func rejectsGarbage() {
        #expect(throws: DomainValidationError.invalidPhone) { try PhoneNumber("123") }
    }
}

@Suite("Payment (задел)")
struct PaymentTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makePayment() throws -> Payment {
        var payment = Payment(id: PaymentID(), bookingId: BookingID(), payerId: UserID(),
                              amount: .rubles(2500), expiresAt: now.addingTimeInterval(900), createdAt: now)
        try payment.issue(paymentURL: URL(string: "https://qr.nspk.ru/AS100")!, qrPayload: "qr")
        return payment
    }

    @Test func repeatedWebhookIsIdempotent() throws {
        var payment = try makePayment()
        try payment.markSucceeded(paidAmount: .rubles(2500))
        try payment.markSucceeded(paidAmount: .rubles(2500))
        #expect(payment.status == .succeeded)
    }

    @Test func refundCannotExceedAmount() throws {
        var payment = try makePayment()
        try payment.markSucceeded(paidAmount: .rubles(2500))
        try payment.requestRefund(.rubles(1000))
        payment.completeRefund(.rubles(1000))
        #expect(payment.status == .partiallyRefunded)
        #expect(throws: PaymentError.refundExceedsAmount) { try payment.requestRefund(.rubles(2000)) }
    }

    @Test func noopGatewayIsDisabled() async {
        await #expect(throws: PaymentGatewayError.featureDisabled) {
            _ = try await NoopPaymentGateway().createSession(
                PaymentSessionRequest(bookingId: BookingID(), payerId: UserID(), amount: .rubles(1), expiresAt: now))
        }
    }
}
