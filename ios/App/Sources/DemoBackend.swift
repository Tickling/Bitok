// App/Sources/DemoBackend.swift — локальный «сервер» для тестирования на одном телефоне.
// Ученик и тренеры работают с общими данными (сохраняются в UserDefaults), поэтому сквозной сценарий
// «запись → подтверждение → тренировка → оценка → прогресс» проверяется без backend.
// Все переходы идут через настоящую доменную модель (BookingDomain, ProgressDomain).
import Foundation
import Observation
import CoreDomain
import BookingDomain
import ProgressDomain
import ChatDomain

struct DemoPerson: Identifiable, Hashable, Sendable {
    let id: UserID
    let name: String
    let phone: String

    var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }
}

/// Тренер: человек + редактируемое описание. Где и когда он тренирует — в его местах (DemoVenue).
struct DemoCoach: Identifiable, Hashable, Sendable {
    let person: DemoPerson
    /// Квалификация: «Мастер спорта», «КМС» и т. п.
    var rank: String
    /// Часы работы текстом: «Пн–Сб, 16:00–22:00».
    var scheduleTitle: String
    /// Базовая цена; для отдельных учеников тренер может задать свою.
    var price: Money
    var about: String = ""
    /// Основное место (первое в списке мест тренера).
    var clubName: String = ""
    var clubAddress: String = ""

    var id: UserID { person.id }
    var name: String { person.name }
}

struct DemoEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UserID
    let title: String
    let body: String
    let date: Date
}

struct DemoMessage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let from: UserID
    let to: UserID
    let text: String
    let date: Date
    /// Системное сообщение о брони: в чате показывается карточка с живым статусом.
    var bookingId: BookingID? = nil
    /// Предложение тренера: конкретный слот, на который ученик может согласиться одной кнопкой.
    var invitation: DemoInvitation? = nil
    /// Запрос между учениками: «сыграем?» или «обменяемся номерами?».
    var peerRequest: DemoPeerRequest? = nil
    /** Подарок: в чате показывается открытка. */
    var giftId: UUID? = nil
    /// Сообщение изменено (время правки).
    var editedAt: Date? = nil
    /// У кого сообщение удалено «только у себя».
    var hiddenFor: [UserID]? = nil
    /// Видео выполнения упражнения (имя файла в Documents/videos).
    var videoFile: String? = nil
}

/// Запрос одного ученика другому. Номера телефонов открываются только после согласия обоих (BR-030.2).
struct DemoPeerRequest: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case playInvite, phoneExchange }
    enum Status: String, Codable, Sendable { case sent, accepted, declined }
    let kind: Kind
    var status: Status
}

struct DemoInvitation: Codable, Hashable, Sendable {
    let slotId: SlotID
    var status: InvitationStatus
    var comment: String?
    /// Бронь, созданная после согласия ученика.
    var bookingId: BookingID?
}

/// Редактируемые данные профиля (FR-002).
struct DemoProfile: Codable, Hashable, Sendable {
    var firstName: String
    var lastName: String
    var city: String
    var discipline: String
    var about: String
    /// Дата рождения. Другим ученикам по умолчанию не видна; тренер видит всегда.
    var birthDate: Date? = nil
    /// Что видят другие ученики: hidden (по умолчанию), year — только год, dayMonth — только день и месяц.
    var birthdayVisibility: String? = nil

    var fullName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

private struct DemoSnapshot: Codable {
    var profiles: [UserID: DemoProfile]? = nil
    var venues: [DemoVenue]? = nil
    var coachInfo: [UserID: DemoCoachInfo]? = nil
    var studentPrices: [UserID: [UserID: Int64]]? = nil
    var groups: [DemoGroupSession]? = nil
    var news: [DemoNews]? = nil
    var listings: [DemoListing]? = nil
    var gifts: [DemoGift]? = nil
    var customExercises: [Exercise]? = nil
    var exerciseResults: [ExerciseResult]? = nil
    var readMarks: [UserID: [UserID: Date]]? = nil
    var noticesSeen: [UserID: Date]? = nil
    var groupBookings: Set<BookingID>? = nil
    var subscriptions: [UserID: Date]? = nil
    var exerciseStars: [UserID: [String: Int]]? = nil
    var trainingVideos: [TrainingVideo]? = nil
    var chatGroups: [DemoChatGroup]? = nil
    var groupMessages: [DemoGroupMessage]? = nil
    var slots: [BookingSlot]
    var bookings: [Booking]
    var records: [ProgressRecord]
    var events: [DemoEvent]
    var messages: [DemoMessage]
    var privacy: PrivacySettings
}

@MainActor
@Observable
final class DemoBackend {
    // Фиксированные ID, чтобы тестовые учётки всегда указывали на одних и тех же людей.
    static let alexeyId = UserID(UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!)
    static let veronikaId = UserID(UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!)
    static let ivanId = UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    static let natashaId = UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000005")!)
    /// Ученик с подпиской «Биток Про» — для проверки камеры-помощника.
    static let dmitryId = UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000006")!)

    /// Тренеры в исходном виде; правки профиля (DemoCoachInfo) и места накладываются в syncCoaches().
    static let baseCoaches: [DemoCoach] = [
        DemoCoach(person: DemoPerson(id: DemoBackend.alexeyId, name: "Алексей Воронов", phone: "+7 900 000-00-01"),
                  rank: "Мастер спорта", scheduleTitle: "Пн–Сб 16:00–22:00, Вс 12:00–16:00", price: .rubles(2500),
                  about: "Русский бильярд, 15 лет тренерского опыта"),
        DemoCoach(person: DemoPerson(id: DemoBackend.veronikaId, name: "Вероника Смирнова", phone: "+7 900 000-00-03"),
                  rank: "КМС, тренер по пулу", scheduleTitle: "Пн, Ср, Пт, Вс 10:00–15:00", price: .rubles(2000),
                  about: "Пул и постановка удара с нуля"),
    ]

    var coaches: [DemoCoach] = DemoBackend.baseCoaches

    let students: [DemoPerson] = [
        DemoPerson(id: DemoBackend.ivanId, name: "Иван Петров", phone: "+7 900 000-00-02"),
        DemoPerson(id: UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!), name: "Мария Соколова", phone: "+7 916 555-01-21"),
        DemoPerson(id: UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!), name: "Олег Морозов", phone: "+7 903 555-01-02"),
        DemoPerson(id: UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000004")!), name: "Анна Романова", phone: "+7 925 555-03-04"),
        DemoPerson(id: DemoBackend.natashaId, name: "Наталья Белова", phone: "+7 900 000-00-04"),
        DemoPerson(id: DemoBackend.dmitryId, name: "Дмитрий Орлов", phone: "+7 900 000-00-05"),
    ]

    var slots: [BookingSlot] = []
    var bookings: [Booking] = []
    private(set) var records: [ProgressRecord] = []
    var events: [DemoEvent] = []
    var messages: [DemoMessage] = []
    private(set) var privacy = PrivacySettings()
    private(set) var profiles: [UserID: DemoProfile] = [:]
    var venues: [DemoVenue] = []
    var coachInfo: [UserID: DemoCoachInfo] = [:]
    var studentPrices: [UserID: [UserID: Int64]] = [:]
    var groups: [DemoGroupSession] = []
    var news: [DemoNews] = []
    var listings: [DemoListing] = []
    var gifts: [DemoGift] = []
    var customExercises: [Exercise] = []
    var exerciseResults: [ExerciseResult] = []
    /// Когда пользователь последний раз открывал чат с собеседником (для «непрочитанных»).
    var readMarks: [UserID: [UserID: Date]] = [:]
    /// Когда пользователь последний раз открывал колокольчик.
    var noticesSeen: [UserID: Date] = [:]
    /// Брони, которые ученик отметил как запись на групповую тренировку.
    var groupBookings: Set<BookingID> = []
    /// Подписка «Биток Про»: до какой даты действует.
    var subscriptions: [UserID: Date] = [:]
    /// Лучшие звёзды ученика за упражнение (самостоятельное выполнение с камерой).
    var exerciseStars: [UserID: [String: Int]] = [:]
    var trainingVideos: [TrainingVideo] = []
    var chatGroupsStore: [DemoChatGroup] = []
    var groupMessagesStore: [DemoGroupMessage] = []

    private static let storageKey = "demoBackend.v6"

    init() {
        // Данные прошлых версий (v1 — один тренер, v2 — без Натальи) пересоздаются.
        UserDefaults.standard.removeObject(forKey: "demoBackend.v1")
        UserDefaults.standard.removeObject(forKey: "demoBackend.v2")
        UserDefaults.standard.removeObject(forKey: "demoBackend.v3")   // v3 — без мест, групп и магазина
        UserDefaults.standard.removeObject(forKey: "demoBackend.v4")
        UserDefaults.standard.removeObject(forKey: "demoBackend.v5")   // v5 — без упражнений   // v4 — без круглосуточного тест-зала
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(DemoSnapshot.self, from: data) {
            apply(snapshot)
        } else {
            seed()
        }
    }

    // MARK: - Люди

    func coach(_ id: UserID) -> DemoCoach? { coaches.first { $0.id == id } }

    func isCoach(_ id: UserID) -> Bool { coach(id) != nil }

    func person(_ id: UserID) -> DemoPerson? {
        guard let base = coaches.first(where: { $0.id == id })?.person ?? students.first(where: { $0.id == id }) else { return nil }
        guard let edited = profiles[id], !edited.fullName.isEmpty else { return base }
        return DemoPerson(id: base.id, name: edited.fullName, phone: base.phone)
    }

    /// Данные профиля для редактирования (по умолчанию — из демо-данных).
    func profile(for id: UserID) -> DemoProfile {
        if let edited = profiles[id] { return edited }
        let parts = (coaches.first { $0.id == id }?.name ?? students.first { $0.id == id }?.name ?? "").split(separator: " ")
        return DemoProfile(firstName: parts.first.map(String.init) ?? "", lastName: parts.dropFirst().joined(separator: " "),
                           city: "Москва", discipline: isCoach(id) && id == DemoBackend.veronikaId ? "Пул" : "Русский бильярд",
                           about: "", birthDate: Self.seedBirthday(id))
    }

    func updateProfile(_ profile: DemoProfile, for id: UserID) {
        profiles[id] = profile
        save()
    }

    func name(_ id: UserID) -> String { person(id)?.name ?? "Ученик" }

    /// Ученики тренера: с бронями у него или перепиской.
    func students(of coachId: UserID) -> [DemoPerson] {
        students.filter { student in
            bookings.contains { $0.studentId == student.id && $0.trainerId == coachId }
                || messages.contains { ($0.from == student.id && $0.to == coachId) || ($0.from == coachId && $0.to == student.id) }
        }
    }

    // MARK: - Слоты и брони

    func slot(_ id: SlotID) -> BookingSlot? { slots.first { $0.id == id } }

    func booking(_ id: BookingID) -> Booking? { bookings.first { $0.id == id } }

    /// Свободные слоты тренера на день, доступные ученику (не раньше чем через 2 часа — BR-005.3).
    /// `student` — показываем только места, открытые этому ученику (у тренера могут быть места «для своих»).
    func freeSlots(of coachId: UserID, on day: Date, for student: UserID? = nil, now: Date = Date()) -> [BookingSlot] {
        slots.filter { $0.trainerId == coachId && Calendar.current.isDate($0.startsAt, inSameDayAs: day)
            && $0.isBookable(at: now) && $0.startsAt.timeIntervalSince(now) >= leadTime($0)
            && isVisible($0, to: student) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// Дни, в которые у тренера есть свободное время.
    func availableDays(of coachId: UserID, for student: UserID? = nil, now: Date = Date()) -> Set<Date> {
        Set(slots.filter { $0.trainerId == coachId && $0.isBookable(at: now) && $0.startsAt.timeIntervalSince(now) >= leadTime($0)
            && isVisible($0, to: student) }
            .map { Calendar.current.startOfDay(for: $0.startsAt) })
    }

    private func isVisible(_ slot: BookingSlot, to student: UserID?) -> Bool {
        guard let student else { return true }
        return canBook(clubId: slot.clubId, student: student)
    }

    /// Все дни, когда тренер работает (для календаря тренера).
    func workingDays(of coachId: UserID) -> Set<Date> {
        Set(slots.filter { $0.trainerId == coachId }.map { Calendar.current.startOfDay(for: $0.startsAt) })
    }

    func bookings(ofStudent id: UserID) -> [Booking] {
        bookings.filter { $0.studentId == id }.sorted { $0.startsAt > $1.startsAt }
    }

    func bookings(of coachId: UserID, on day: Date) -> [Booking] {
        bookings.filter { $0.trainerId == coachId && Calendar.current.isDate($0.startsAt, inSameDayAs: day) && $0.status != .rescheduled }
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// Свободные слоты тренера на день (для календаря тренера, без ограничения «за 2 часа»).
    func coachFreeSlots(of coachId: UserID, on day: Date, now: Date = Date()) -> [BookingSlot] {
        slots.filter { $0.trainerId == coachId && Calendar.current.isDate($0.startsAt, inSameDayAs: day) && $0.isBookable(at: now) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    func pendingRequests(of coachId: UserID) -> [Booking] {
        bookings.filter { $0.trainerId == coachId && $0.status == .awaitingCoachApproval }.sorted { $0.startsAt < $1.startsAt }
    }

    func isEvaluated(_ bookingId: BookingID) -> Bool { records.contains { $0.bookingId == bookingId } }

    func record(for bookingId: BookingID) -> ProgressRecord? { records.first { $0.bookingId == bookingId } }

    // MARK: - Команды (через доменную модель)

    @discardableResult
    func book(slotId: SlotID, studentId: UserID, comment: String?) throws -> Booking {
        let now = Date()
        guard let index = slots.firstIndex(where: { $0.id == slotId }) else { throw BookingError.slotNotAvailable }
        var slot = slots[index]
        guard slot.startsAt.timeIntervalSince(now) >= leadTime(slot) else {
            throw BookingError.leadTimeViolation(minimumMinutes: Int(leadTime(slot) / 60))
        }
        let active = bookings.filter { $0.studentId == studentId && $0.status.holdsSlot }
        guard active.filter({ $0.status == .awaitingCoachApproval }).count < 3 else {
            throw BookingError.pendingLimitExceeded(limit: 3)
        }
        let overlaps = active.contains { other in
            let otherEnd = other.startsAt.addingTimeInterval(TimeInterval(other.durationMinutes * 60))
            return other.startsAt < slot.endsAt && slot.startsAt < otherEnd
        }
        guard !overlaps else { throw BookingError.overlappingBooking }

        guard canBook(clubId: slot.clubId, student: studentId) else { throw BookingError.forbidden }
        // Цена — индивидуальная для ученика, если тренер её задал.
        let booking = try Booking.request(id: BookingID(), slot: priced(slot, for: studentId), studentId: studentId,
                                          comment: comment, now: now)
        try slot.hold(until: booking.approvalExpiresAt, now: now)
        slots[index] = slot
        bookings.append(booking)
        notify(booking.trainerId, "Новая заявка", "\(name(studentId)) · \(Self.when(booking.startsAt))")
        post(from: studentId, to: booking.trainerId,
             text: comment.map { "Заявка на тренировку. \($0)" } ?? "Заявка на тренировку", bookingId: booking.id)
        save()
        return booking
    }

    func approve(_ id: BookingID) throws {
        guard let current = booking(id) else { throw BookingError.slotNotAvailable }
        try update(id) { booking, now in
            try booking.approve(by: .coach(current.trainerId), decision: .notRequired, now: now)
        }
        mutateSlot(current.slotId) { $0.markBooked() }
        if let confirmed = booking(id) { LocalNotifier.shared.scheduleReminder(for: confirmed, studentName: name(confirmed.studentId)) }
        notify(current.studentId, "Тренировка подтверждена ✓", "\(name(current.trainerId)) · \(Self.when(current.startsAt))")
        post(from: current.trainerId, to: current.studentId, text: "Тренировка подтверждена ✓ Жду вас!", bookingId: id)
        save()
    }

    /// `note` — свой текст в чат вместо стандартного (например, когда тренер сразу предлагает другое время).
    func reject(_ id: BookingID, reason: CancellationReason, note: String? = nil) throws {
        guard let current = booking(id) else { throw BookingError.slotNotAvailable }
        try update(id) { booking, now in
            try booking.reject(by: .coach(current.trainerId), reason: reason, now: now)
        }
        mutateSlot(current.slotId) { $0.release() }
        notify(current.studentId, "Заявка отклонена", "\(Self.when(current.startsAt)) · \(Self.reasonTitle(reason.code))")
        post(from: current.trainerId, to: current.studentId,
             text: note ?? "Заявка отклонена: \(Self.reasonTitle(reason.code).lowercased()). Выберите другое время", bookingId: id)
        save()
    }

    /// Тренер отвечает на заявку своим временем: заявка закрывается, ученику приходит предложение нового слота.
    func counterPropose(bookingId: BookingID, slotId: SlotID, comment: String?) throws {
        guard let current = booking(bookingId), let slot = slot(slotId) else { throw BookingError.slotNotAvailable }
        guard slot.isBookable(at: Date()) else { throw BookingError.slotAlreadyTaken }
        if current.status == .awaitingCoachApproval {
            try reject(bookingId, reason: CancellationReason(code: .scheduleConflict),
                       note: "В \(Fmt.time(current.startsAt)) не получится — предлагаю другое время 👇")
        } else if current.status == .confirmed {
            try cancel(bookingId, by: current.trainerId, reason: CancellationReason(code: .coachUnavailable))
        }
        try proposeSlot(coachId: current.trainerId, studentId: current.studentId, slotId: slotId, comment: comment)
    }

    func cancel(_ id: BookingID, by actor: UserID, reason: CancellationReason?) throws {
        guard let current = booking(id) else { throw BookingError.slotNotAvailable }
        let role: BookingActor = isCoach(actor) ? .coach(actor) : .student(actor)
        try update(id) { booking, now in
            try booking.cancel(by: role, reason: reason, freeCancellationHours: 12, now: now)
        }
        mutateSlot(current.slotId) { $0.release() }
        LocalNotifier.shared.cancelReminder(for: id)
        let target = isCoach(actor) ? current.studentId : current.trainerId
        notify(target, "Тренировка отменена", "\(name(actor)) · \(Self.when(current.startsAt))")
        post(from: actor, to: target, text: "Тренировка отменена", bookingId: id)
        save()
    }

    /// Демо: «время тренировки наступило» — завершаем, даже если по часам она ещё впереди.
    func complete(_ id: BookingID) throws {
        guard let current = booking(id) else { throw BookingError.slotNotAvailable }
        try update(id) { booking, now in
            try booking.complete(now: max(now, booking.startsAt))
        }
        notify(current.studentId, "Тренировка завершена", "Тренер скоро оценит ваши навыки")
        post(from: current.trainerId, to: current.studentId, text: "Спасибо за тренировку! Скоро пришлю оценку", bookingId: id)
        save()
    }

    func markNoShow(_ id: BookingID) throws {
        guard let current = booking(id) else { throw BookingError.slotNotAvailable }
        try update(id) { booking, now in
            try booking.markNoShow(by: .coach(current.trainerId), now: max(now, booking.startsAt.addingTimeInterval(16 * 60)))
        }
        save()
    }

    @discardableResult
    func evaluate(bookingId: BookingID, scores: [MetricKey: Int], comment: String?) throws -> ProgressRecord {
        guard let booking = booking(bookingId) else { throw BookingError.slotNotAvailable }
        guard booking.status == .completed else {
            throw BookingError.invalidStateTransition(from: booking.status, to: .completed)
        }
        let before = progress(for: booking.studentId).current
        let record = ProgressRecord(id: ID(), studentId: booking.studentId, trainerId: booking.trainerId,
                                    bookingId: bookingId, scores: try EvaluationScores(scores), comment: comment,
                                    recommendations: [], assignedLessonIds: [], evaluatedAt: Date())
        records.removeAll { $0.bookingId == bookingId }
        records.append(record)
        let after = progress(for: booking.studentId).current
        let deltas = after.delta(from: before).filter { $0.value != 0 }
            .map { "\($0.key.title) \($0.value > 0 ? "+" : "")\($0.value)" }
        notify(booking.studentId, "Новая оценка тренера", deltas.isEmpty ? "Откройте «Прогресс»" : deltas.joined(separator: " · "))
        post(from: booking.trainerId, to: booking.studentId,
             text: "Оценка тренировки: " + (deltas.isEmpty ? "смотрите «Прогресс»" : deltas.joined(separator: ", ")), bookingId: bookingId)
        save()
        return record
    }

    // MARK: - Предложение времени тренером (FR-017, FR-028)

    /// Тренер предлагает ученику свой свободный слот. Слот не блокируется, пока ученик не ответит.
    func proposeSlot(coachId: UserID, studentId: UserID, slotId: SlotID, comment: String?) throws {
        guard let slot = slot(slotId), slot.trainerId == coachId else { throw BookingError.forbidden }
        guard slot.isBookable(at: Date()) else { throw BookingError.slotAlreadyTaken }
        messages.append(DemoMessage(id: UUID(), from: coachId, to: studentId,
                                    text: "Предлагаю тренировку", date: Date(),
                                    invitation: DemoInvitation(slotId: slotId, status: .sent, comment: comment, bookingId: nil)))
        notify(studentId, "\(name(coachId)) предлагает тренировку", Self.when(slot.startsAt))
        save()
    }

    enum InvitationAnswer { case accept, decline, otherTime }

    /// Ответ ученика. «Принять» сразу создаёт подтверждённую бронь — время уже согласовано с тренером.
    @discardableResult
    func answerInvitation(messageId: UUID, by studentId: UserID, _ answer: InvitationAnswer) throws -> Booking? {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              var invitation = messages[index].invitation, messages[index].to == studentId else { throw BookingError.forbidden }
        guard invitation.status == .sent else { throw BookingError.invalidStateTransition(from: .confirmed, to: .confirmed) }
        let coachId = messages[index].from
        var created: Booking?
        switch answer {
        case .accept:
            let now = Date()
            guard let slotIndex = slots.firstIndex(where: { $0.id == invitation.slotId }) else { throw BookingError.slotNotAvailable }
            var slot = slots[slotIndex]
            guard slot.isBookable(at: now) else { throw BookingError.slotAlreadyTaken }
            let overlaps = bookings.contains { other in
                other.studentId == studentId && other.status.holdsSlot
                    && other.startsAt < slot.endsAt
                    && slot.startsAt < other.startsAt.addingTimeInterval(TimeInterval(other.durationMinutes * 60))
            }
            guard !overlaps else { throw BookingError.overlappingBooking }
            let booking = try Booking.assignByCoach(id: BookingID(), slot: priced(slot, for: studentId), studentId: studentId,
                                                    coachId: coachId, isCoachesStudent: true, decision: .notRequired, now: now)
            slot.markBooked()
            slots[slotIndex] = slot
            bookings.append(booking)
            invitation.status = .accepted
            invitation.bookingId = booking.id
            created = booking
            LocalNotifier.shared.scheduleReminder(for: booking, studentName: name(studentId))
            post(from: studentId, to: coachId, text: "Принимаю предложение ✓", bookingId: booking.id)
            notify(coachId, "\(name(studentId)) принял предложение", Self.when(booking.startsAt))
        case .decline:
            invitation.status = .declined
            post(from: studentId, to: coachId, text: "Не смогу в это время", bookingId: nil)
            notify(coachId, "\(name(studentId)) отказался", "Предложение тренировки отклонено")
        case .otherTime:
            invitation.status = .counterProposed
            post(from: studentId, to: coachId, text: "Это время не подходит — выберу другое в календаре", bookingId: nil)
        }
        messages[index].invitation = invitation
        save()
        return created
    }

    // MARK: - Обмен учеников местами (тренер)

    /// С кем можно поменять запись: другие подтверждённые будущие тренировки того же тренера с другими учениками.
    /// Сначала — тренировки в тот же день.
    func swapCandidates(for bookingId: BookingID, now: Date = Date()) -> [Booking] {
        guard let source = booking(bookingId), source.status == .confirmed, source.startsAt > now else { return [] }
        let calendar = Calendar.current
        return bookings.filter {
            $0.id != source.id && $0.trainerId == source.trainerId && $0.studentId != source.studentId
                && $0.status == .confirmed && $0.startsAt > now
        }
        .sorted { lhs, rhs in
            let lhsSame = calendar.isDate(lhs.startsAt, inSameDayAs: source.startsAt)
            let rhsSame = calendar.isDate(rhs.startsAt, inSameDayAs: source.startsAt)
            return lhsSame != rhsSame ? lhsSame : lhs.startsAt < rhs.startsAt
        }
    }

    /// Тренер меняет двух учеников местами: старые брони → RESCHEDULED, слоты пересобираются,
    /// каждому ученику создаётся подтверждённая бронь на время другого. Оба получают сообщение в чат.
    func swap(_ firstId: BookingID, with secondId: BookingID, by coachId: UserID) throws {
        let now = Date()
        guard let first = booking(firstId), let second = booking(secondId) else { throw BookingError.slotNotAvailable }
        guard first.trainerId == coachId, second.trainerId == coachId else { throw BookingError.forbidden }
        guard first.studentId != second.studentId else { throw BookingError.overlappingBooking }
        for item in [first, second] where item.status != .confirmed || item.startsAt <= now {
            throw BookingError.invalidStateTransition(from: item.status, to: .rescheduled)
        }
        // У ученика не должно быть другой тренировки, пересекающейся с новым временем.
        func overlaps(_ studentId: UserID, _ start: Date, minutes: Int, ignoring: BookingID) -> Bool {
            let end = start.addingTimeInterval(TimeInterval(minutes * 60))
            return bookings.contains { other in
                other.id != ignoring && other.studentId == studentId && other.status.holdsSlot
                    && other.startsAt < end
                    && start < other.startsAt.addingTimeInterval(TimeInterval(other.durationMinutes * 60))
            }
        }
        guard !overlaps(first.studentId, second.startsAt, minutes: second.durationMinutes, ignoring: first.id),
              !overlaps(second.studentId, first.startsAt, minutes: first.durationMinutes, ignoring: second.id)
        else { throw BookingError.overlappingBooking }

        // Проверяем лимит переносов до любых изменений, чтобы не оставить данные наполовину.
        var firstOld = first, secondOld = second
        try firstOld.markRescheduled(now: now)
        try secondOld.markRescheduled(now: now)
        guard let firstSlotIndex = slots.firstIndex(where: { $0.id == first.slotId }),
              let secondSlotIndex = slots.firstIndex(where: { $0.id == second.slotId }) else { throw BookingError.slotNotAvailable }
        var firstSlot = slots[firstSlotIndex], secondSlot = slots[secondSlotIndex]
        firstSlot.release()
        secondSlot.release()
        // Ученик первой брони получает слот второй и наоборот.
        let firstNew = try Booking.assignByCoach(id: BookingID(), slot: priced(secondSlot, for: first.studentId),
                                                 studentId: first.studentId, coachId: coachId,
                                                 isCoachesStudent: true, decision: .notRequired, now: now)
        let secondNew = try Booking.assignByCoach(id: BookingID(), slot: priced(firstSlot, for: second.studentId),
                                                  studentId: second.studentId, coachId: coachId,
                                                  isCoachesStudent: true, decision: .notRequired, now: now)
        firstSlot.markBooked()
        secondSlot.markBooked()
        slots[firstSlotIndex] = firstSlot
        slots[secondSlotIndex] = secondSlot
        if let index = bookings.firstIndex(where: { $0.id == first.id }) { bookings[index] = firstOld }
        if let index = bookings.firstIndex(where: { $0.id == second.id }) { bookings[index] = secondOld }
        bookings.append(contentsOf: [firstNew, secondNew])
        for (old, new) in [(first, firstNew), (second, secondNew)] {
            LocalNotifier.shared.cancelReminder(for: old.id)
            LocalNotifier.shared.scheduleReminder(for: new, studentName: name(new.studentId))
        }

        for (old, new, partner) in [(first, firstNew, second.studentId), (second, secondNew, first.studentId)] {
            let partnerName = name(partner).split(separator: " ").first.map(String.init) ?? name(partner)
            let text = "Поменял вас местами с \(partnerName): теперь \(Self.when(new.startsAt)) вместо \(Fmt.time(old.startsAt))"
            post(from: coachId, to: old.studentId, text: text, bookingId: new.id)
            notify(old.studentId, "Время тренировки изменено", "\(Self.when(new.startsAt)) вместо \(Fmt.time(old.startsAt))")
        }
        save()
    }

    // MARK: - Ученик ↔ ученик: сыграть и обменяться номерами (FR-030)

    /// Оба согласились обменяться номерами — телефоны видны друг другу.
    func phonesShared(_ a: UserID, _ b: UserID) -> Bool {
        conversation(between: a, and: b).contains { $0.peerRequest?.kind == .phoneExchange && $0.peerRequest?.status == .accepted }
    }

    /// Есть ли неотвеченный запрос такого типа в этом диалоге.
    func hasPendingRequest(_ kind: DemoPeerRequest.Kind, between a: UserID, and b: UserID) -> Bool {
        conversation(between: a, and: b).contains { $0.peerRequest?.kind == kind && $0.peerRequest?.status == .sent }
    }

    func sendPeerRequest(_ kind: DemoPeerRequest.Kind, from: UserID, to: UserID) throws {
        guard from != to, !isCoach(from), !isCoach(to) else { throw BookingError.forbidden }
        guard !hasPendingRequest(kind, between: from, and: to) else { return }
        if kind == .phoneExchange && phonesShared(from, to) { return }
        let text = kind == .playInvite ? "Давай сыграем партию? 🎱" : "Хотите обменяться номерами телефонов?"
        messages.append(DemoMessage(id: UUID(), from: from, to: to, text: text, date: Date(),
                                    peerRequest: DemoPeerRequest(kind: kind, status: .sent)))
        notify(to, kind == .playInvite ? "\(name(from)) предлагает сыграть" : "\(name(from)) предлагает обменяться номерами", text)
        save()
    }

    func answerPeerRequest(messageId: UUID, by userId: UserID, accept: Bool) throws {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              var request = messages[index].peerRequest, messages[index].to == userId else { throw BookingError.forbidden }
        guard request.status == .sent else { return }
        request.status = accept ? .accepted : .declined
        messages[index].peerRequest = request
        let author = messages[index].from
        switch (request.kind, accept) {
        case (.playInvite, true):
            post(from: userId, to: author, text: "Давай! Когда тебе удобно?", bookingId: nil)
            notify(author, "\(name(userId)) согласна(ен) сыграть", "Договоритесь о времени в чате")
        case (.phoneExchange, true):
            notify(author, "Номера открыты 📞", "\(name(userId)): \(person(userId)?.phone ?? "")")
        case (_, false):
            notify(author, "\(name(userId)) отказался(ась)", request.kind == .playInvite ? "Приглашение сыграть" : "Обмен номерами")
        }
        save()
    }

    // MARK: - Прогресс

    func progress(for studentId: UserID) -> StudentProgress {
        var progress = StudentProgress(studentId: studentId)
        for record in records.filter({ $0.studentId == studentId }).sorted(by: { $0.evaluatedAt < $1.evaluatedAt }) {
            progress.apply(record)
        }
        return progress
    }

    func history(for studentId: UserID) -> [ProgressSnapshot] {
        var metrics = PlayerMetrics()
        return records.filter { $0.studentId == studentId }.sorted { $0.evaluatedAt < $1.evaluatedAt }.map { record in
            metrics = metrics.applying(record.scores)
            return ProgressSnapshot(date: record.evaluatedAt, metrics: metrics)
        }
    }

    func setPrivacy(_ settings: PrivacySettings) -> PrivacySettings {
        privacy = settings
        save()
        return settings
    }

    // MARK: - Чат и уведомления

    func conversation(between a: UserID, and b: UserID) -> [DemoMessage] {
        // Сообщения, удалённые «только у себя», первый участник (тот, кто смотрит) не видит.
        messages.filter { (($0.from == a && $0.to == b) || ($0.from == b && $0.to == a)) && !($0.hiddenFor ?? []).contains(a) }
            .sorted { $0.date < $1.date }
    }

    func lastMessage(_ a: UserID, _ b: UserID) -> DemoMessage? { conversation(between: a, and: b).last }

    func send(from: UserID, to: UserID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        post(from: from, to: to, text: trimmed, bookingId: nil)
        notify(to, "Сообщение от \(name(from))", trimmed)
        save()
    }

    /// Собеседники: у ученика — все тренеры и игроки, с которыми есть переписка; у тренера — его ученики.
    func chatPartners(of userId: UserID) -> [DemoPerson] {
        let partners = isCoach(userId)
            ? students(of: userId)
            : coaches.map(\.person) + students.filter { $0.id != userId && !conversation(between: userId, and: $0.id).isEmpty }
        return partners.sorted {
            (lastMessage(userId, $0.id)?.date ?? .distantPast) > (lastMessage(userId, $1.id)?.date ?? .distantPast)
        }
    }

    func events(for userId: UserID) -> [DemoEvent] {
        events.filter { $0.userId == userId }.sorted { $0.date > $1.date }
    }

    // MARK: - «Игроки клуба» (FR-030)

    /// Другие ученики клуба для ученика.
    func players(for userId: UserID) -> [DemoPerson] { students.filter { $0.id != userId } }

    /// Рейтинг, видимый другим ученикам. Демо приватности: Олег скрыл прогресс → nil (в UI — 🔒).
    func publicRating(of studentId: UserID) -> Int? {
        studentId == students[2].id ? nil : progress(for: studentId).overallRating
    }

    // MARK: - Сброс

    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        slots = []
        bookings = []
        records = []
        events = []
        messages = []
        privacy = PrivacySettings()
        profiles = [:]
        venues = []
        coachInfo = [:]
        studentPrices = [:]
        groups = []
        news = []
        listings = []
        gifts = []
        customExercises = []
        exerciseResults = []
        readMarks = [:]
        noticesSeen = [:]
        groupBookings = []
        subscriptions = [:]
        exerciseStars = [:]
        trainingVideos = []
        chatGroupsStore = []
        groupMessagesStore = []
        coaches = Self.baseCoaches
        seed()
    }

    // MARK: - Private

    func update(_ id: BookingID, _ change: (inout Booking, Date) throws -> Void) throws {
        guard let index = bookings.firstIndex(where: { $0.id == id }) else { throw BookingError.slotNotAvailable }
        var booking = bookings[index]
        try change(&booking, Date())
        bookings[index] = booking
    }

    func mutateSlot(_ id: SlotID, _ change: (inout BookingSlot) -> Void) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        var slot = slots[index]
        change(&slot)
        slots[index] = slot
    }

    func notify(_ userId: UserID, _ title: String, _ body: String) {
        events.append(DemoEvent(id: UUID(), userId: userId, title: title, body: body, date: Date()))
        // Системное уведомление на телефон (демо: все учётки на одном устройстве — в подзаголовке указан получатель).
        if !seeding { LocalNotifier.shared.post(to: name(userId), title: title, body: body) }
    }

    func post(from: UserID, to: UserID, text: String, bookingId: BookingID?) {
        messages.append(DemoMessage(id: UUID(), from: from, to: to, text: text, date: Date(), bookingId: bookingId))
    }

    func save() {
        let snapshot = DemoSnapshot(profiles: profiles, venues: venues, coachInfo: coachInfo, studentPrices: studentPrices,
                                    groups: groups, news: news, listings: listings, gifts: gifts, customExercises: customExercises,
                                    exerciseResults: exerciseResults, readMarks: readMarks, noticesSeen: noticesSeen,
                                    groupBookings: groupBookings, subscriptions: subscriptions, exerciseStars: exerciseStars,
                                    trainingVideos: trainingVideos, chatGroups: chatGroupsStore, groupMessages: groupMessagesStore,
                                    slots: slots, bookings: bookings, records: records, events: events,
                                    messages: messages, privacy: privacy)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func apply(_ snapshot: DemoSnapshot) {
        slots = snapshot.slots
        bookings = snapshot.bookings
        records = snapshot.records
        events = snapshot.events
        messages = snapshot.messages
        privacy = snapshot.privacy
        profiles = snapshot.profiles ?? [:]
        venues = snapshot.venues ?? []
        coachInfo = snapshot.coachInfo ?? [:]
        studentPrices = snapshot.studentPrices ?? [:]
        groups = snapshot.groups ?? []
        news = snapshot.news ?? []
        listings = snapshot.listings ?? []
        gifts = snapshot.gifts ?? []
        customExercises = snapshot.customExercises ?? []
        exerciseResults = snapshot.exerciseResults ?? []
        readMarks = snapshot.readMarks ?? [:]
        noticesSeen = snapshot.noticesSeen ?? [:]
        groupBookings = snapshot.groupBookings ?? []
        subscriptions = snapshot.subscriptions ?? [:]
        exerciseStars = snapshot.exerciseStars ?? [:]
        trainingVideos = snapshot.trainingVideos ?? []
        chatGroupsStore = snapshot.chatGroups ?? []
        groupMessagesStore = snapshot.groupMessages ?? []
        syncCoaches()
    }

    /// Начальные данные: расписания двух тренеров на 3 недели, история Ивана, заявки других учеников.
    /// Во время заполнения начальными данными системные уведомления не показываются.
    private var seeding = false

    private func seed() {
        seeding = true
        defer { seeding = false }
        seedVenues()
        syncCoaches()
        for coach in coaches {
            generateSlots(for: coach.id, fromDay: -45)
        }

        let alexey = coaches[0].id, veronika = coaches[1].id
        let ivan = students[0].id, maria = students[1].id, oleg = students[2].id, anna = students[3].id
        let natasha = DemoBackend.natashaId
        // История Ивана у Алексея: 4 завершённые тренировки с оценками — радар и графики сразу заполнены.
        let ivanHistory: [(Int, [MetricKey: Int])] = [
            (-40, [.stanceAndStroke: 55, .aiming: 50, .positionPlay: 42, .cueBallControl: 35, .tacticalThinking: 45]),
            (-25, [.stanceAndStroke: 60, .aiming: 62, .positionPlay: 46, .cueBallControl: 40, .tacticalThinking: 50]),
            (-10, [.stanceAndStroke: 63, .aiming: 70, .positionPlay: 50, .cueBallControl: 43, .tacticalThinking: 55]),
            (-4, [.stanceAndStroke: 65, .aiming: 76, .positionPlay: 52, .cueBallControl: 45, .tacticalThinking: 58]),
        ]
        for (offset, scores) in ivanHistory {
            if let booking = seedBooking(coach: alexey, student: ivan, dayOffset: offset, finalStatus: .completed),
               let evaluation = try? EvaluationScores(scores) {
                records.append(ProgressRecord(id: ID(), studentId: ivan, trainerId: alexey, bookingId: booking.id,
                                              scores: evaluation, comment: "Хороший прогресс в прицеливании, выход пока нестабилен",
                                              recommendations: ["Упражнение «Лесенка» на выход"], assignedLessonIds: [],
                                              evaluatedAt: booking.startsAt.addingTimeInterval(2 * 3600)))
            }
        }
        // Ученики Алексея
        seedBooking(coach: alexey, student: maria, dayOffset: -1, finalStatus: .completed)        // ждёт оценки
        seedBooking(coach: alexey, student: oleg, dayOffset: 1, finalStatus: .confirmed)
        // Иван и Наталья подряд в один день (16:00 — Олег, 17:00 — Иван, 18:00 — Наталья): можно поменять местами.
        let ivanNext = seedBooking(coach: alexey, student: ivan, dayOffset: 1, finalStatus: .confirmed)
        let natashaNext = seedBooking(coach: alexey, student: natasha, dayOffset: 1, finalStatus: .confirmed)
        seedBooking(coach: alexey, student: anna, dayOffset: 2, finalStatus: .awaitingCoachApproval)
        // Ученики Вероники
        seedBooking(coach: veronika, student: anna, dayOffset: -2, finalStatus: .completed)       // ждёт оценки
        seedBooking(coach: veronika, student: oleg, dayOffset: 2, finalStatus: .awaitingCoachApproval)
        seedBooking(coach: veronika, student: maria, dayOffset: 4, finalStatus: .confirmed)

        messages = [
            DemoMessage(id: UUID(), from: alexey, to: ivan, text: "Привет! Жду на тренировке, поработаем над выходом на дальний борт 🎱",
                        date: Date().addingTimeInterval(-3 * 3600)),
            DemoMessage(id: UUID(), from: natasha, to: alexey, text: "Алексей, добрый день! А можно завтра пораньше? В 18:00 не очень удобно",
                        date: Date().addingTimeInterval(-2 * 3600)),
            DemoMessage(id: UUID(), from: veronika, to: ivan, text: "Здравствуйте! Если захотите попробовать пул — записывайтесь на утро 🙂",
                        date: Date().addingTimeInterval(-5 * 3600)),
        ]
        // Карточки подтверждённых тренировок в чатах — из них тренер меняет учеников местами.
        for (student, booking) in [(ivan, ivanNext), (natasha, natashaNext)] {
            guard let booking else { continue }
            messages.append(DemoMessage(id: UUID(), from: alexey, to: student, text: "Тренировка подтверждена ✓ Жду вас!",
                                        date: Date().addingTimeInterval(-4 * 3600), bookingId: booking.id))
        }
        seedExtras()
        seedExerciseResults()
        // Дмитрий — с подпиской «Биток Про» на год и тренировкой у Алексея.
        subscriptions[DemoBackend.dmitryId] = Calendar.current.date(byAdding: .year, value: 1, to: Date())
        seedBooking(coach: alexey, student: DemoBackend.dmitryId, dayOffset: 3, finalStatus: .confirmed)
        notify(DemoBackend.dmitryId, "Биток Про подключён ✨", "Откройте «Прогресс» → «Упражнения» → «Камера-помощник»")
        for student in [ivan, natasha] {
            notify(student, "Добро пожаловать в «Биток»", "Выберите тренера и запишитесь во вкладке «Календарь»")
        }
        for coach in coaches {
            notify(coach.id, "Добро пожаловать в «Биток»", "Новые заявки появятся в «Календаре» и в чате")
        }
        save()
    }

    /// Бронь в первом слоте тренера в нужный день.
    @discardableResult
    private func seedBooking(coach: UserID, student: UserID, dayOffset: Int, finalStatus: BookingStatus) -> Booking? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) else { return nil }
        // Ближайший рабочий день тренера, начиная с нужного (у Вероники не каждый день рабочий).
        let mainClub = venues.first { $0.coachId == coach }?.clubId
        let candidates = slots.indices.filter { slots[$0].trainerId == coach && slots[$0].status == .available
            && slots[$0].clubId == mainClub
            && slots[$0].startsAt >= day }
            .sorted { slots[$0].startsAt < slots[$1].startsAt }
        guard let index = candidates.first else { return nil }
        var slot = slots[index]
        let start = slot.startsAt
        let requestedAt = start.addingTimeInterval(-3 * 86_400)
        guard var booking = try? Booking.request(id: BookingID(), slot: slot, studentId: student,
                                                 comment: nil, now: requestedAt),
              (try? slot.hold(until: booking.approvalExpiresAt, now: requestedAt)) != nil
        else { return nil }
        if finalStatus == .confirmed || finalStatus == .completed {
            try? booking.approve(by: .coach(coach), decision: .notRequired, now: requestedAt.addingTimeInterval(3600))
            slot.markBooked()
        }
        if finalStatus == .completed {
            try? booking.complete(now: start.addingTimeInterval(3600))
        }
        slots[index] = slot
        bookings.append(booking)
        return booking
    }

    static func when(_ date: Date) -> String {
        Fmt.stamp(date)
    }

    static func reasonTitle(_ code: CancellationReasonCode) -> String {
        switch code {
        case .illness: "Болезнь"
        case .scheduleConflict: "Неудобное время"
        case .coachUnavailable: "Тренер занят"
        case .clubClosed: "Клуб закрыт"
        case .other: "Другое"
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case BookingError.slotAlreadyTaken, BookingError.slotNotAvailable: "Этот слот уже заняли. Выберите другое время."
        case BookingError.leadTimeViolation: "Записаться можно не позднее чем за 2 часа до начала."
        case BookingError.pendingLimitExceeded(let limit): "У вас уже \(limit) заявки ждут тренера."
        case BookingError.overlappingBooking: "У вас уже есть тренировка в это время."
        case BookingError.invalidStateTransition: "Это действие недоступно в текущем статусе."
        case BookingError.reasonRequired: "Укажите причину."
        case BookingError.forbidden: "Нет прав на это действие."
        default: "Что-то пошло не так. Попробуйте ещё раз."
        }
    }
}

/// Адаптер порта ProgressRepository к демо-серверу — экран «Прогресс» из ProgressKit работает без изменений.
struct BackendProgressRepository: ProgressRepository {
    let backend: DemoBackend

    func evaluate(bookingId: BookingID, scores: EvaluationScores, comment: String?, recommendations: [String]) async throws -> ProgressRecord {
        try await backend.evaluate(bookingId: bookingId, scores: scores.values, comment: comment)
    }

    func progress(studentId: UserID) async throws -> StudentProgress {
        await backend.progress(for: studentId)
    }

    func history(studentId: UserID, from: Date, to: Date) async throws -> [ProgressSnapshot] {
        await backend.history(for: studentId)
    }

    func privacy(studentId: UserID) async throws -> PrivacySettings {
        await backend.privacy
    }

    func updatePrivacy(studentId: UserID, _ settings: PrivacySettings) async throws -> PrivacySettings {
        await backend.setPrivacy(settings)
    }
}
