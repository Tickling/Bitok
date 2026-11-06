// App/Sources/DemoBackend.swift — локальный «сервер» для тестирования на одном телефоне.
// Ученик и тренеры работают с общими данными (сохраняются в UserDefaults), поэтому сквозной сценарий
// «запись → подтверждение → тренировка → оценка → прогресс» проверяется без backend.
// Все переходы идут через настоящую доменную модель (BookingDomain, ProgressDomain).
import Foundation
import Observation
import CoreDomain
import BookingDomain
import ProgressDomain

struct DemoPerson: Identifiable, Hashable, Sendable {
    let id: UserID
    let name: String
    let phone: String

    var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }
}

/// Тренер: человек + клуб и описание расписания.
struct DemoCoach: Identifiable, Hashable, Sendable {
    let person: DemoPerson
    let rank: String
    let clubName: String
    let clubAddress: String
    let scheduleTitle: String
    let price: Money
    /// Рабочие дни (Calendar weekday: 1 — воскресенье … 7 — суббота) и часы начала тренировок.
    let weekdays: Set<Int>
    let hours: [Int]

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
}

private struct DemoSnapshot: Codable {
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

    let coaches: [DemoCoach] = [
        DemoCoach(person: DemoPerson(id: DemoBackend.alexeyId, name: "Алексей Воронов", phone: "+7 900 000-00-01"),
                  rank: "Мастер спорта", clubName: "Престиж", clubAddress: "Москва, ул. Тверская, 10",
                  scheduleTitle: "Пн–Сб, вечер 16:00–22:00", price: .rubles(2500),
                  weekdays: [2, 3, 4, 5, 6, 7], hours: [16, 17, 18, 19, 20, 21]),
        DemoCoach(person: DemoPerson(id: DemoBackend.veronikaId, name: "Вероника Смирнова", phone: "+7 900 000-00-03"),
                  rank: "КМС, тренер по пулу", clubName: "Пирамида", clubAddress: "Москва, ул. Арбат, 25",
                  scheduleTitle: "Пн, Ср, Пт, Вс — утро и день 10:00–15:00", price: .rubles(2000),
                  weekdays: [1, 2, 4, 6], hours: [10, 11, 12, 13, 14]),
    ]

    let students: [DemoPerson] = [
        DemoPerson(id: DemoBackend.ivanId, name: "Иван Петров", phone: "+7 900 000-00-02"),
        DemoPerson(id: UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!), name: "Мария Соколова", phone: "+7 916 555-01-21"),
        DemoPerson(id: UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!), name: "Олег Морозов", phone: "+7 903 555-01-02"),
        DemoPerson(id: UserID(UUID(uuidString: "00000000-0000-0000-0000-000000000004")!), name: "Анна Романова", phone: "+7 925 555-03-04"),
    ]

    private(set) var slots: [BookingSlot] = []
    private(set) var bookings: [Booking] = []
    private(set) var records: [ProgressRecord] = []
    private(set) var events: [DemoEvent] = []
    private(set) var messages: [DemoMessage] = []
    private(set) var privacy = PrivacySettings()

    private static let storageKey = "demoBackend.v2"

    init() {
        UserDefaults.standard.removeObject(forKey: "demoBackend.v1")   // данные старой версии с одним тренером
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
        coach(id)?.person ?? students.first { $0.id == id }
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
    func freeSlots(of coachId: UserID, on day: Date, now: Date = Date()) -> [BookingSlot] {
        slots.filter { $0.trainerId == coachId && Calendar.current.isDate($0.startsAt, inSameDayAs: day)
            && $0.isBookable(at: now) && $0.startsAt.timeIntervalSince(now) >= 2 * 3600 }
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// Дни, в которые у тренера есть свободное время.
    func availableDays(of coachId: UserID, now: Date = Date()) -> Set<Date> {
        Set(slots.filter { $0.trainerId == coachId && $0.isBookable(at: now) && $0.startsAt.timeIntervalSince(now) >= 2 * 3600 }
            .map { Calendar.current.startOfDay(for: $0.startsAt) })
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
        guard slot.startsAt.timeIntervalSince(now) >= 2 * 3600 else { throw BookingError.leadTimeViolation(minimumMinutes: 120) }
        let active = bookings.filter { $0.studentId == studentId && $0.status.holdsSlot }
        guard active.filter({ $0.status == .awaitingCoachApproval }).count < 3 else {
            throw BookingError.pendingLimitExceeded(limit: 3)
        }
        let overlaps = active.contains { other in
            let otherEnd = other.startsAt.addingTimeInterval(TimeInterval(other.durationMinutes * 60))
            return other.startsAt < slot.endsAt && slot.startsAt < otherEnd
        }
        guard !overlaps else { throw BookingError.overlappingBooking }

        let booking = try Booking.request(id: BookingID(), slot: slot, studentId: studentId, comment: comment, now: now)
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
        notify(current.studentId, "Тренировка подтверждена ✓", "\(name(current.trainerId)) · \(Self.when(current.startsAt))")
        post(from: current.trainerId, to: current.studentId, text: "Тренировка подтверждена ✓ Жду вас!", bookingId: id)
        save()
    }

    func reject(_ id: BookingID, reason: CancellationReason) throws {
        guard let current = booking(id) else { throw BookingError.slotNotAvailable }
        try update(id) { booking, now in
            try booking.reject(by: .coach(current.trainerId), reason: reason, now: now)
        }
        mutateSlot(current.slotId) { $0.release() }
        notify(current.studentId, "Заявка отклонена", "\(Self.when(current.startsAt)) · \(Self.reasonTitle(reason.code))")
        post(from: current.trainerId, to: current.studentId,
             text: "Заявка отклонена: \(Self.reasonTitle(reason.code).lowercased()). Выберите другое время", bookingId: id)
        save()
    }

    func cancel(_ id: BookingID, by actor: UserID, reason: CancellationReason?) throws {
        guard let current = booking(id) else { throw BookingError.slotNotAvailable }
        let role: BookingActor = isCoach(actor) ? .coach(actor) : .student(actor)
        try update(id) { booking, now in
            try booking.cancel(by: role, reason: reason, freeCancellationHours: 12, now: now)
        }
        mutateSlot(current.slotId) { $0.release() }
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
        messages.filter { ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a) }.sorted { $0.date < $1.date }
    }

    func lastMessage(_ a: UserID, _ b: UserID) -> DemoMessage? { conversation(between: a, and: b).last }

    func send(from: UserID, to: UserID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        post(from: from, to: to, text: trimmed, bookingId: nil)
        notify(to, "Сообщение от \(name(from))", trimmed)
        save()
    }

    /// Собеседники: у ученика — все тренеры, у тренера — его ученики. Свежие диалоги сверху.
    func chatPartners(of userId: UserID) -> [DemoPerson] {
        let partners = isCoach(userId) ? students(of: userId) : coaches.map(\.person)
        return partners.sorted {
            (lastMessage(userId, $0.id)?.date ?? .distantPast) > (lastMessage(userId, $1.id)?.date ?? .distantPast)
        }
    }

    func events(for userId: UserID) -> [DemoEvent] {
        events.filter { $0.userId == userId }.sorted { $0.date > $1.date }
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
        seed()
    }

    // MARK: - Private

    private func update(_ id: BookingID, _ change: (inout Booking, Date) throws -> Void) throws {
        guard let index = bookings.firstIndex(where: { $0.id == id }) else { throw BookingError.slotNotAvailable }
        var booking = bookings[index]
        try change(&booking, Date())
        bookings[index] = booking
    }

    private func mutateSlot(_ id: SlotID, _ change: (inout BookingSlot) -> Void) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        var slot = slots[index]
        change(&slot)
        slots[index] = slot
    }

    private func notify(_ userId: UserID, _ title: String, _ body: String) {
        events.append(DemoEvent(id: UUID(), userId: userId, title: title, body: body, date: Date()))
    }

    private func post(from: UserID, to: UserID, text: String, bookingId: BookingID?) {
        messages.append(DemoMessage(id: UUID(), from: from, to: to, text: text, date: Date(), bookingId: bookingId))
    }

    private func save() {
        let snapshot = DemoSnapshot(slots: slots, bookings: bookings, records: records, events: events,
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
    }

    /// Начальные данные: расписания двух тренеров на 3 недели, история Ивана, заявки других учеников.
    private func seed() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for (coachIndex, coach) in coaches.enumerated() {
            for dayOffset in -45...21 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                      coach.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
                for hour in coach.hours {
                    guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                          let slot = try? BookingSlot(id: SlotID(), trainerId: coach.id, clubId: ClubID(),
                                                      tableNumber: (hour + coachIndex) % 4 + 1, startsAt: start,
                                                      durationMinutes: 60, price: coach.price)
                    else { continue }
                    slots.append(slot)
                }
            }
        }

        let alexey = coaches[0].id, veronika = coaches[1].id
        let ivan = students[0].id, maria = students[1].id, oleg = students[2].id, anna = students[3].id
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
        seedBooking(coach: alexey, student: anna, dayOffset: 2, finalStatus: .awaitingCoachApproval)
        // Ученики Вероники
        seedBooking(coach: veronika, student: anna, dayOffset: -2, finalStatus: .completed)       // ждёт оценки
        seedBooking(coach: veronika, student: oleg, dayOffset: 2, finalStatus: .awaitingCoachApproval)
        seedBooking(coach: veronika, student: maria, dayOffset: 4, finalStatus: .confirmed)

        messages = [
            DemoMessage(id: UUID(), from: alexey, to: ivan, text: "Привет! Жду на тренировке, поработаем над выходом на дальний борт 🎱",
                        date: Date().addingTimeInterval(-3 * 3600)),
            DemoMessage(id: UUID(), from: veronika, to: ivan, text: "Здравствуйте! Если захотите попробовать пул — записывайтесь на утро 🙂",
                        date: Date().addingTimeInterval(-5 * 3600)),
        ]
        notify(ivan, "Добро пожаловать в «Биток»", "Выберите тренера и запишитесь во вкладке «Календарь»")
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
        let candidates = slots.indices.filter { slots[$0].trainerId == coach && slots[$0].status == .available
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
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
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
