// App/Sources/AppContainer.swift — composition root: здесь выбираются адаптеры (Ports & Adapters).
import Foundation
import Observation
import CoreDomain
import ProgressDomain

@MainActor
@Observable
final class AppContainer {
    var role: UserRole = .student
    var flags = ClientFlags()
    /// Выбранная вкладка и путь в чате — чтобы после записи сразу открыть диалог с тренером.
    var selectedTab: AppTab = .calendar
    var chatPath: [UserID] = []
    /// Тренер, выбранный в календаре ученика (можно задать из чата: «Другое время»).
    var selectedCoachId: UserID = DemoBackend.alexeyId
    /// Текущая демо-учётка; nil — показывается экран входа.
    private(set) var account: DemoAccount? = nil

    /// Локальный демо-сервер. В проде вместо него — адаптеры CoreNetwork к BFF.
    let backend: DemoBackend
    /// Порт платёжного контура. MVP: NoopPaymentGateway; v1.0: BFFPaymentGateway — ядро не меняется.
    let paymentGateway: PaymentGateway
    let progress: ProgressRepository

    init(backend: DemoBackend, paymentGateway: PaymentGateway) {
        self.backend = backend
        self.paymentGateway = paymentGateway
        self.progress = BackendProgressRepository(backend: backend)
        if let saved = UserDefaults.standard.string(forKey: Self.accountKey), let restored = DemoAccount(rawValue: saved) {
            self.account = restored
            self.role = restored.role
        }
        applyUITestArguments()
    }

    // MARK: - Скриншоты для «Помощи» (CI запускает приложение в симуляторе с аргументами)

    /// Начальный раздел внутри вкладок: «players», «market», «week», «venues», «day».
    var uiPage: String?

    private func applyUITestArguments() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "uiAccount"), let account = DemoAccount(rawValue: raw) else { return }
        if defaults.bool(forKey: "uiReset") { backend.reset() }
        signIn(account)
        switch defaults.string(forKey: "uiTab") {
        case "people": selectedTab = .people
        case "chat": selectedTab = .chat
        case "content": selectedTab = .content
        case "profile": selectedTab = .profile
        default: selectedTab = .calendar
        }
        let people = ["alexey": DemoBackend.alexeyId, "veronika": DemoBackend.veronikaId,
                      "ivan": DemoBackend.ivanId, "natasha": DemoBackend.natashaId]
        if let chat = defaults.string(forKey: "uiChat"), let id = people[chat] { chatPath = [id] }
        uiPage = defaults.string(forKey: "uiPage")
    }

    static func demo() -> AppContainer {
        AppContainer(backend: DemoBackend(), paymentGateway: NoopPaymentGateway())
    }

    /// ID текущего пользователя: тренер Алексей, тренер Вероника или ученик Иван.
    var currentUserId: UserID {
        account?.userId ?? DemoBackend.ivanId
    }

    private static let accountKey = "demoAccount"

    func signIn(_ account: DemoAccount) {
        self.account = account
        role = account.role
        UserDefaults.standard.set(account.rawValue, forKey: Self.accountKey)
    }

    /// Открыть диалог с собеседником (используется после записи и из карточки брони).
    func openChat(with userId: UserID) {
        chatPath = [userId]
        selectedTab = .chat
    }

    /// Открыть календарь записи к конкретному тренеру.
    func openBooking(with coachId: UserID) {
        selectedCoachId = coachId
        selectedTab = .calendar
    }

    func signOut() {
        selectedTab = .calendar
        chatPath = []
        account = nil
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
    }

    func handle(_ url: URL) {
        // bitok://booking/{id} — из события календаря; https://bitok.app/pay/return — возврат из банка.
    }
}

enum AppTab: Hashable {
    case calendar, people, chat, content, profile
}

struct ClientFlags: Decodable, Sendable {
    var paymentsUIEnabled = false
    var shopEnabled = false
    var minSupportedVersion = "1.0.0"
}
