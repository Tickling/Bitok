// App/Sources/BackendExtras.swift — места тренировок, индивидуальные цены, групповые тренировки,
// новости и маркет. Хранится в том же снимке DemoBackend.
import Foundation
import CoreDomain
import BookingDomain

// MARK: - Модели

/// Место, где тренер проводит тренировки, со своим расписанием и кругом учеников.
struct DemoVenue: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    let coachId: UserID
    var name: String
    var address: String
    /// Дни недели (Calendar weekday: 1 — Вс, 2 — Пн … 7 — Сб).
    var weekdays: Set<Int>
    /// Часы начала тренировок.
    var hours: [Int]
    /// true — записаться могут только выбранные ученики.
    var onlySelected: Bool = false
    var allowedStudents: Set<UserID> = []
    var clubId: ClubID = ClubID()
    /// Тестовое место: слоты каждый час, записаться можно за 5 минут до начала (проверка уведомлений).
    var isTest: Bool? = nil

    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    static func weekdayTitle(_ weekday: Int) -> String {
        ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"][(weekday - 1) % 7]
    }

    var daysTitle: String {
        let ordered = Self.weekdayOrder.filter(weekdays.contains)
        return ordered.isEmpty ? "Дни не выбраны" : ordered.map(Self.weekdayTitle).joined(separator: ", ")
    }

    var hoursTitle: String {
        guard let first = hours.min(), let last = hours.max() else { return "Время не выбрано" }
        return String(format: "%02d:00–%02d:00", first, last + 1)
    }
}

/// Правки тренера в своём профиле.
struct DemoCoachInfo: Codable, Hashable, Sendable {
    var rank: String
    var scheduleTitle: String
    var about: String
    var priceRubles: Int64
}

/// Групповая (игровая) тренировка: несколько учеников в одно время.
struct DemoGroupSession: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    let coachId: UserID
    var clubId: ClubID
    var title: String
    var startsAt: Date
    var durationMinutes: Int
    var capacity: Int
    var priceRubles: Int64
    var participants: [UserID] = []
    var cancelled = false

    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    var freePlaces: Int { max(0, capacity - participants.count) }
}

struct DemoNews: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case tournament, news
        var title: String { self == .tournament ? "Турнир" : "Новость" }
    }

    var id: UUID = UUID()
    let authorId: UserID
    var kind: Kind
    var title: String
    var body: String
    var eventDate: Date?
    var date: Date = Date()
    /// Фото (MediaStore) и ссылка на видео.
    var imageId: String? = nil
    var videoURL: String? = nil
}

enum MarketCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case cues, chalk, gloves, accessories, repair, service
    var id: Self { self }
    var title: String {
        switch self {
        case .cues: "Кии"
        case .chalk: "Мелки"
        case .gloves: "Перчатки"
        case .accessories: "Аксессуары"
        case .repair: "Ремонт кия"
        case .service: "Обслуживание кия"
        }
    }
    var symbol: String {
        switch self {
        case .cues: "line.diagonal"
        case .chalk: "cube"
        case .gloves: "hand.raised"
        case .accessories: "bag"
        case .repair: "wrench.and.screwdriver"
        case .service: "sparkles"
        }
    }
    /// Услуга, а не товар.
    var isService: Bool { self == .repair || self == .service }
}

struct DemoListing: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    let sellerId: UserID
    var category: MarketCategory
    var title: String
    var details: String
    var priceRubles: Int64?
    var date: Date = Date()
    /// Первое (главное) фото.
    var imageId: String? = nil
    /// Остальные фото (всего до 10).
    var extraImageIds: [String]? = nil
    /// Характеристики: «Длина — 160 см».
    var specs: [ListingSpec]? = nil

    var allImageIds: [String] { [imageId].compactMap { $0 } + (extraImageIds ?? []) }
}

struct ListingSpec: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var value: String
}

extension MarketCategory {
    /// Подсказки характеристик по категории — чтобы не писать их в описании.
    var suggestedSpecs: [String] {
        switch self {
        case .cues: ["Длина", "Вес", "Материал", "Наклейка", "Мастер / бренд", "Состояние"]
        case .chalk: ["Бренд", "Цвет", "Количество"]
        case .gloves: ["Размер", "Рука", "Материал", "Состояние"]
        case .accessories: ["Тип", "Бренд", "Состояние"]
        case .repair, .service: ["Срок", "Гарантия", "Где"]
        }
    }
}

// MARK: - Места

extension DemoBackend {
    func venues(of coachId: UserID) -> [DemoVenue] { venues.filter { $0.coachId == coachId } }

    func venue(clubId: ClubID) -> DemoVenue? { venues.first { $0.clubId == clubId } }

    func venue(forSlot slotId: SlotID) -> DemoVenue? { slot(slotId).flatMap { venue(clubId: $0.clubId) } }

    /// «Флагман, стол 2» и адрес для карточек.
    func placeTitle(slotId: SlotID) -> String {
        guard let slot = slot(slotId) else { return "Клуб" }
        let name = venue(clubId: slot.clubId)?.name ?? coach(slot.trainerId)?.clubName ?? "Клуб"
        return slot.tableNumber.map { "\(name), стол \($0)" } ?? name
    }

    func placeAddress(slotId: SlotID) -> String {
        slot(slotId).flatMap { venue(clubId: $0.clubId)?.address } ?? ""
    }

    /// Минимальное время до начала, когда ещё можно записаться: 2 часа, в тест-зале — 5 минут.
    func leadTime(_ slot: BookingSlot) -> TimeInterval {
        venue(clubId: slot.clubId)?.isTest == true ? 5 * 60 : 2 * 3600
    }

    func canBook(clubId: ClubID, student: UserID) -> Bool {
        guard let venue = venue(clubId: clubId) else { return true }
        return !venue.onlySelected || venue.allowedStudents.contains(student)
    }

    /// Сохранить место и пересобрать будущие свободные слоты тренера. Занятые слоты не трогаются.
    func saveVenue(_ venue: DemoVenue) {
        if let index = venues.firstIndex(where: { $0.id == venue.id }) {
            venues[index] = venue
        } else {
            venues.append(venue)
        }
        regenerateSlots(for: venue.coachId)
    }

    func deleteVenue(_ venue: DemoVenue) {
        venues.removeAll { $0.id == venue.id }
        regenerateSlots(for: venue.coachId)
    }

    func regenerateSlots(for coachId: UserID) {
        let now = Date()
        slots.removeAll { $0.trainerId == coachId && $0.status == .available && $0.startsAt > now }
        generateSlots(for: coachId, fromDay: 0)
        syncCoaches()
        save()
    }

    /// Слоты по правилам мест на дни [fromDay, 21] от сегодня. Время, уже занятое другим местом
    /// или групповой тренировкой, пропускается.
    func generateSlots(for coachId: UserID, fromDay: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let coach = coach(coachId) else { return }
        for (venueIndex, venue) in venues(of: coachId).enumerated() {
            // У тест-зала слоты только с сегодняшнего дня и на неделю вперёд.
            let range = venue.isTest == true ? max(fromDay, 0)...7 : fromDay...21
            for offset in range {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      venue.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
                for hour in venue.hours.sorted() {
                    guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                          start > Date() || (fromDay < 0 && venue.isTest != true),
                          !slots.contains(where: { $0.trainerId == coachId && $0.startsAt == start }),
                          !groups.contains(where: { $0.coachId == coachId && !$0.cancelled && $0.startsAt < start.addingTimeInterval(3600) && start < $0.endsAt }),
                          let slot = try? BookingSlot(id: SlotID(), trainerId: coachId, clubId: venue.clubId,
                                                      tableNumber: (hour + venueIndex) % 4 + 1, startsAt: start,
                                                      durationMinutes: 60, price: coach.price)
                    else { continue }
                    slots.append(slot)
                }
            }
        }
    }

    /// Применяет правки профиля тренеров и подставляет основное место.
    func syncCoaches() {
        coaches = Self.baseCoaches.map { base in
            var coach = base
            if let info = coachInfo[base.id] {
                coach.rank = info.rank
                coach.scheduleTitle = info.scheduleTitle
                coach.about = info.about
                coach.price = .rubles(info.priceRubles)
            }
            if let main = venues.first(where: { $0.coachId == base.id }) {
                coach.clubName = main.name
                coach.clubAddress = main.address
            }
            return coach
        }
    }

    func updateCoachInfo(_ info: DemoCoachInfo, for coachId: UserID) {
        coachInfo[coachId] = info
        syncCoaches()
        save()
    }

    func coachInfo(for coachId: UserID) -> DemoCoachInfo {
        if let info = coachInfo[coachId] { return info }
        let coach = coach(coachId)
        return DemoCoachInfo(rank: coach?.rank ?? "", scheduleTitle: coach?.scheduleTitle ?? "", about: coach?.about ?? "",
                             priceRubles: NSDecimalNumber(decimal: coach?.price.decimalValue ?? 0).int64Value)
    }

    // MARK: Цены

    /// Цена тренировки для конкретного ученика: индивидуальная или базовая.
    func price(coach coachId: UserID, student: UserID) -> Money {
        if let custom = studentPrices[coachId]?[student] { return .rubles(custom) }
        return coach(coachId)?.price ?? .rubles(0)
    }

    func hasCustomPrice(coach coachId: UserID, student: UserID) -> Bool { studentPrices[coachId]?[student] != nil }

    func setPrice(_ rubles: Int64?, coach coachId: UserID, student: UserID) {
        var prices = studentPrices[coachId] ?? [:]
        prices[student] = rubles
        studentPrices[coachId] = prices
        save()
    }

    func priced(_ slot: BookingSlot, for student: UserID) -> BookingSlot {
        var copy = slot
        copy.price = price(coach: slot.trainerId, student: student)
        return copy
    }

    // MARK: - Групповые тренировки

    func groups(of coachId: UserID, includePast: Bool = false) -> [DemoGroupSession] {
        groups.filter { $0.coachId == coachId && !$0.cancelled && (includePast || $0.endsAt > Date()) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    func groups(of coachId: UserID, on day: Date) -> [DemoGroupSession] {
        groups.filter { $0.coachId == coachId && !$0.cancelled && Calendar.current.isDate($0.startsAt, inSameDayAs: day) }
    }

    /// Групповые, доступные ученику (с учётом закрытых мест).
    func openGroups(of coachId: UserID, for student: UserID) -> [DemoGroupSession] {
        groups(of: coachId).filter { canBook(clubId: $0.clubId, student: student) }
    }

    func groups(ofStudent student: UserID) -> [DemoGroupSession] {
        groups.filter { !$0.cancelled && $0.participants.contains(student) && $0.endsAt > Date() }.sorted { $0.startsAt < $1.startsAt }
    }

    func group(_ id: UUID) -> DemoGroupSession? { groups.first { $0.id == id } }

    /// Тренер создаёт групповую тренировку; свободные индивидуальные слоты в это время убираются.
    func createGroup(_ session: DemoGroupSession) throws {
        guard session.startsAt > Date() else { throw BookingError.leadTimeViolation(minimumMinutes: 0) }
        let busy = bookings.contains {
            $0.trainerId == session.coachId && $0.status.holdsSlot && $0.startsAt < session.endsAt
                && session.startsAt < $0.startsAt.addingTimeInterval(TimeInterval($0.durationMinutes * 60))
        }
        guard !busy else { throw BookingError.overlappingBooking }
        slots.removeAll {
            $0.trainerId == session.coachId && $0.status == .available && $0.startsAt < session.endsAt && session.startsAt < $0.endsAt
        }
        groups.append(session)
        for student in students(of: session.coachId) where canBook(clubId: session.clubId, student: student.id) {
            notify(student.id, "Новая групповая тренировка", "\(session.title) · \(Self.when(session.startsAt))")
        }
        save()
    }

    func join(group id: UUID, student: UserID) throws {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { throw BookingError.slotNotAvailable }
        var session = groups[index]
        guard !session.participants.contains(student) else { return }
        guard session.freePlaces > 0 else { throw BookingError.slotAlreadyTaken }
        guard canBook(clubId: session.clubId, student: student) else { throw BookingError.forbidden }
        session.participants.append(student)
        groups[index] = session
        post(from: student, to: session.coachId,
             text: "Записался(ась) на групповую: \(session.title), \(Self.when(session.startsAt))", bookingId: nil)
        notify(session.coachId, "Запись на групповую", "\(name(student)) · \(session.participants.count)/\(session.capacity)")
        save()
    }

    func leave(group id: UUID, student: UserID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].participants.removeAll { $0 == student }
        let session = groups[index]
        post(from: student, to: session.coachId, text: "Не смогу прийти на групповую \(Self.when(session.startsAt))", bookingId: nil)
        notify(session.coachId, "Отмена в групповой", "\(name(student)) · \(session.participants.count)/\(session.capacity)")
        save()
    }

    func cancelGroup(_ id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].cancelled = true
        let session = groups[index]
        for student in session.participants {
            post(from: session.coachId, to: student, text: "Групповая тренировка \(Self.when(session.startsAt)) отменена", bookingId: nil)
            notify(student, "Групповая отменена", session.title)
        }
        regenerateSlots(for: session.coachId)
    }

    // MARK: - Новости и маркет

    func publish(_ item: DemoNews) {
        news.insert(item, at: 0)
        for student in students where item.authorId != student.id {
            notify(student.id, item.kind == .tournament ? "🏆 \(item.title)" : item.title, "\(name(item.authorId)) · Контент")
        }
        save()
    }

    func deleteNews(_ id: UUID) {
        news.removeAll { $0.id == id }
        save()
    }

    func publish(_ listing: DemoListing) {
        listings.insert(listing, at: 0)
        save()
    }

    func deleteListing(_ id: UUID) {
        listings.removeAll { $0.id == id }
        save()
    }

    // MARK: - Начальные данные

    func seedVenues() {
        let alexey = DemoBackend.alexeyId, veronika = DemoBackend.veronikaId
        venues = [
            DemoVenue(coachId: alexey, name: "Флагман", address: "Москва, ул. Тверская, 10",
                      weekdays: [2, 3, 4, 5, 6, 7], hours: [16, 17, 18, 19, 20, 21]),
            DemoVenue(coachId: alexey, name: "Тиджон", address: "Москва, Ленинский пр., 45",
                      weekdays: [1], hours: [12, 13, 14, 15], onlySelected: true,
                      allowedStudents: [DemoBackend.ivanId, DemoBackend.natashaId]),
            DemoVenue(coachId: veronika, name: "Пирамида", address: "Москва, ул. Арбат, 25",
                      weekdays: [1, 2, 4, 6], hours: [10, 11, 12, 13, 14]),
            // Круглосуточный тест-зал: слот каждый час с 00:00, запись за 5 минут — чтобы проверить уведомления.
            DemoVenue(coachId: alexey, name: "Тест-зал 24/7", address: "Для проверки уведомлений",
                      weekdays: [1, 2, 3, 4, 5, 6, 7], hours: Array(0...23), isTest: true),
        ]
    }

    /// Групповая тренировка, новости и объявления для демо.
    func seedExtras() {
        let calendar = Calendar.current
        let alexey = DemoBackend.alexeyId, veronika = DemoBackend.veronikaId
        // Ближайшая среда, 20:00, «Флагман» — игровая тренировка на 6 человек.
        if let flagship = venues.first(where: { $0.coachId == alexey }),
           let wednesday = calendar.nextDate(after: Date().addingTimeInterval(86_400), matching: DateComponents(hour: 20, weekday: 4),
                                             matchingPolicy: .nextTime) {
            let session = DemoGroupSession(coachId: alexey, clubId: flagship.clubId, title: "Игровая тренировка",
                                           startsAt: wednesday, durationMinutes: 120, capacity: 6, priceRubles: 1200,
                                           participants: [students[1].id, students[3].id])
            slots.removeAll { $0.trainerId == alexey && $0.status == .available && $0.startsAt < session.endsAt && session.startsAt < $0.endsAt }
            groups = [session]
        }
        let tournamentDay = calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: Date()))
            .flatMap { calendar.date(bySettingHour: 11, minute: 0, second: 0, of: $0) }
        news = [
            DemoNews(authorId: alexey, kind: .tournament, title: "Кубок «Флагмана» — открыта регистрация",
                     body: "Свободная пирамида, сетка на 32 игрока. Взнос 1 500 ₽, призы — кии и медали. Запись у тренера в чате.",
                     eventDate: tournamentDay, date: Date().addingTimeInterval(-6 * 3600),
                     videoURL: "https://www.youtube.com/results?search_query=русский+бильярд+свободная+пирамида"),
            DemoNews(authorId: veronika, kind: .tournament, title: "Женский турнир по пулу в «Пирамиде»",
                     body: "Восьмёрка, до 3 побед. Новичкам — отдельная группа.",
                     eventDate: tournamentDay.flatMap { calendar.date(byAdding: .day, value: 7, to: $0) },
                     date: Date().addingTimeInterval(-26 * 3600)),
            DemoNews(authorId: alexey, kind: .news, title: "Итоги осеннего рейтинга",
                     body: "Иван Петров поднялся на 3-е место клуба. Поздравляем! 🎉", date: Date().addingTimeInterval(-3 * 86_400)),
        ]
        listings = [
            DemoListing(sellerId: alexey, category: .cues, title: "Кий «Веста», клён, 160 см",
                        details: "Б/у полгода, наклейка новая, чехол в подарок", priceRubles: 18_000),
            DemoListing(sellerId: alexey, category: .chalk, title: "Мел Taom V10, 2 шт.",
                        details: "Новый, в упаковке", priceRubles: 2_400),
            DemoListing(sellerId: veronika, category: .gloves, title: "Перчатка для пула, размер M",
                        details: "Для правой и левой руки, есть в наличии", priceRubles: 900),
            DemoListing(sellerId: alexey, category: .repair, title: "Замена наклейки и колпачка",
                        details: "За 1 день, наклейки Kamui и Tiger", priceRubles: 1_500),
            DemoListing(sellerId: veronika, category: .service, title: "Чистка и полировка древка",
                        details: "Уберу липкость и грязь, восстановлю скольжение", priceRubles: 800),
        ]
    }
}
