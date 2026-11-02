// App/Sources/AppContainer.swift — composition root: здесь выбираются адаптеры (Ports & Adapters).
import Foundation
import Observation
import CoreDomain
import BookingDomain
import ProgressDomain
import AchievementDomain
import ChatDomain

@MainActor
@Observable
final class AppContainer {
    var role: UserRole
    var flags: ClientFlags
    let currentUserId: UserID
    let coachId: UserID

    // Порты → адаптеры. MVP: NoopPaymentGateway; v1.0: BFFPaymentGateway — ядро не меняется.
    let paymentGateway: PaymentGateway
    let slots: SlotRepository
    let bookings: BookingRepository
    let progress: ProgressRepository

    init(role: UserRole, flags: ClientFlags, currentUserId: UserID, coachId: UserID,
         paymentGateway: PaymentGateway, slots: SlotRepository, bookings: BookingRepository, progress: ProgressRepository) {
        self.role = role
        self.flags = flags
        self.currentUserId = currentUserId
        self.coachId = coachId
        self.paymentGateway = paymentGateway
        self.slots = slots
        self.bookings = bookings
        self.progress = progress
    }

    /// Демо-сборка: локальные данные без backend (для симулятора и демонстраций).
    static func demo() -> AppContainer {
        let coach = UserID()
        let student = UserID()
        let store = DemoBookingStore(coachId: coach, studentId: student)
        return AppContainer(role: .student, flags: ClientFlags(), currentUserId: student, coachId: coach,
                            paymentGateway: NoopPaymentGateway(), slots: store, bookings: store,
                            progress: DemoProgressRepository())
    }

    func handle(_ url: URL) {
        // bitok://booking/{id} — из события календаря; https://bitok.app/pay/return — возврат из банка.
    }
}

struct ClientFlags: Decodable, Sendable {
    var paymentsUIEnabled = false
    var shopEnabled = false
    var minSupportedVersion = "1.0.0"
}
