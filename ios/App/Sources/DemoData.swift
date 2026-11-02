// App/Sources/DemoData.swift — демо-адаптеры портов (в проде — адаптеры CoreNetwork к BFF).
import Foundation
import CoreDomain
import BookingDomain
import ProgressDomain
import AchievementDomain
import ChatDomain

actor DemoBookingStore: SlotRepository, BookingRepository {
    private var slotsById: [SlotID: BookingSlot] = [:]
    private var bookingsById: [BookingID: Booking] = [:]
    private var idempotency: [UUID: BookingID] = [:]
    private let studentId: UserID

    init(coachId: UserID, studentId: UserID) {
        self.studentId = studentId
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for dayOffset in [2, 3, 5, 8, 10, 12, 15, 17, 19] {
            for hour in [16, 17, 18, 19, 20, 21] {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                      let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                      let slot = try? BookingSlot(id: SlotID(), trainerId: coachId, clubId: ClubID(), tableNumber: 4,
                                                  startsAt: start, durationMinutes: 60, price: .rubles(2500))
                else { continue }
                slotsById[slot.id] = slot
            }
        }
    }

    func slots(trainerId: UserID, in interval: DateInterval) async throws -> [BookingSlot] {
        slotsById.values.filter { $0.trainerId == trainerId && interval.contains($0.startsAt) && $0.isBookable(at: Date()) }
    }

    func slot(id: SlotID) async throws -> BookingSlot {
        guard let slot = slotsById[id] else { throw BookingError.slotNotAvailable }
        return slot
    }

    func create(slotId: SlotID, comment: String?, idempotencyKey: UUID) async throws -> Booking {
        if let existing = idempotency[idempotencyKey], let booking = bookingsById[existing] { return booking }
        guard var slot = slotsById[slotId] else { throw BookingError.slotNotAvailable }
        let booking = try Booking.request(id: BookingID(), slot: slot, studentId: studentId, comment: comment, now: Date())
        try slot.hold(until: booking.approvalExpiresAt, now: Date())
        slotsById[slotId] = slot
        bookingsById[booking.id] = booking
        idempotency[idempotencyKey] = booking.id
        return booking
    }

    func booking(id: BookingID) async throws -> Booking {
        guard let booking = bookingsById[id] else { throw BookingError.slotNotAvailable }
        return booking
    }

    func changeStatus(id: BookingID, action: BookingAction, reason: CancellationReason?, expectedVersion: Int) async throws -> Booking {
        try await booking(id: id)
    }

    func history(studentId: UserID, scope: BookingHistoryScope, cursor: String?, limit: Int) async throws -> Page<Booking> {
        Page(items: Array(bookingsById.values), nextCursor: nil)
    }

    nonisolated func updates(for bookingId: BookingID) -> AsyncStream<Booking> {
        AsyncStream { $0.finish() }
    }
}

struct DemoProgressRepository: ProgressRepository {
    func evaluate(bookingId: BookingID, scores: EvaluationScores, comment: String?, recommendations: [String]) async throws -> ProgressRecord {
        ProgressRecord(id: ID(), studentId: UserID(), trainerId: UserID(), bookingId: bookingId, scores: scores,
                       comment: comment, recommendations: recommendations, assignedLessonIds: [], evaluatedAt: Date())
    }

    func progress(studentId: UserID) async throws -> StudentProgress {
        var progress = StudentProgress(studentId: studentId)
        for (index, scores) in Self.evaluations.enumerated() {
            progress.apply(ProgressRecord(id: ID(), studentId: studentId, trainerId: UserID(), bookingId: BookingID(),
                                          scores: try EvaluationScores(scores), comment: nil, recommendations: [],
                                          assignedLessonIds: [], evaluatedAt: Date().addingTimeInterval(Double(index - 6) * 7 * 86_400)))
        }
        return progress
    }

    func history(studentId: UserID, from: Date, to: Date) async throws -> [ProgressSnapshot] {
        var metrics = PlayerMetrics()
        return try Self.evaluations.enumerated().map { index, scores in
            metrics = metrics.applying(try EvaluationScores(scores))
            return ProgressSnapshot(date: to.addingTimeInterval(Double(index - 6) * 14 * 86_400), metrics: metrics)
        }
    }

    func privacy(studentId: UserID) async throws -> PrivacySettings { PrivacySettings() }

    func updatePrivacy(studentId: UserID, _ settings: PrivacySettings) async throws -> PrivacySettings { settings }

    private static let evaluations: [[MetricKey: Int]] = [
        [.stanceAndStroke: 55, .aiming: 50, .positionPlay: 42, .cueBallControl: 35, .tacticalThinking: 45],
        [.stanceAndStroke: 58, .aiming: 58, .positionPlay: 45, .cueBallControl: 38, .tacticalThinking: 48],
        [.stanceAndStroke: 60, .aiming: 63, .positionPlay: 47, .cueBallControl: 40, .tacticalThinking: 52],
        [.stanceAndStroke: 62, .aiming: 70, .positionPlay: 50, .cueBallControl: 42, .tacticalThinking: 55],
        [.stanceAndStroke: 63, .aiming: 74, .positionPlay: 52, .cueBallControl: 44, .tacticalThinking: 58],
        [.stanceAndStroke: 64, .aiming: 78, .positionPlay: 55, .cueBallControl: 46, .tacticalThinking: 60],
    ]
}

enum DemoContent {
    static let medalCards: [MedalCard] = [
        MedalCard(tournamentId: ID(), tournamentTitle: "Кубок «Престижа»", date: Date().addingTimeInterval(-10 * 86_400),
                  clubName: "Престиж", place: 1, medal: .gold, matchesWon: 4, matchesPlayed: 4, ballsPotted: 61,
                  defeatedOpponents: ["Сергей К.", "Анна Р."]),
        MedalCard(tournamentId: ID(), tournamentTitle: "Осенний кубок", date: Date().addingTimeInterval(-40 * 86_400),
                  clubName: "Престиж", place: 3, medal: .bronze, matchesWon: 3, matchesPlayed: 4, ballsPotted: 48,
                  defeatedOpponents: ["Сергей К.", "Дмитрий Л.", "Олег М."]),
        MedalCard(tournamentId: ID(), tournamentTitle: "Турнир новичков", date: Date().addingTimeInterval(-90 * 86_400),
                  clubName: "Престиж", place: 9, medal: .participant, matchesWon: 1, matchesPlayed: 2, ballsPotted: 22,
                  defeatedOpponents: ["Ксения Л."]),
    ]

    static func stats(for student: UserID) -> TournamentStats {
        var stats = TournamentStats(studentId: student)
        for card in medalCards.reversed() {
            stats.record(result: TournamentResult(tournamentId: card.tournamentId, studentId: student, place: card.place,
                                                  medal: card.medal, points: TournamentResult.points(for: card.place),
                                                  recordedAt: card.date), matches: [])
        }
        return stats
    }

    static let players: [PlayerCard] = [
        PlayerCard(id: UserID(), displayName: "Сергей Ковалёв", levelTitle: "Продвинутый", specialTitle: "Чемпион клуба",
                   frameCode: "frame.bronze", overallRating: 61, medalsCount: 5),
        PlayerCard(id: UserID(), displayName: "Дмитрий Лебедев", levelTitle: "Любитель", specialTitle: "Турнирный боец",
                   frameCode: "frame.steel"),
        PlayerCard(id: UserID(), displayName: "Анна Романова", levelTitle: "Продвинутый", specialTitle: "Снайпер",
                   overallRating: 67, medalsCount: 2),
    ]
}
