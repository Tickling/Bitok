// AchievementKit/Sources/AchievementDomain/Tournament.swift
import Foundation
import CoreDomain

public enum TournamentFormat: String, Codable, Sendable {
    case singleElimination = "SINGLE_ELIMINATION"
    case doubleElimination = "DOUBLE_ELIMINATION"
    case roundRobin = "ROUND_ROBIN"
}

public enum TournamentStatus: String, Codable, Sendable {
    case draft = "DRAFT"
    case registrationOpen = "REGISTRATION_OPEN"
    case registrationClosed = "REGISTRATION_CLOSED"
    case inProgress = "IN_PROGRESS"
    case finished = "FINISHED"
    case cancelled = "CANCELLED"
}

/// Медаль за турнир. Каждый, кто сыграл хотя бы один матч, получает минимум медаль участника.
public enum Medal: String, Codable, Sendable, CaseIterable {
    case gold = "GOLD", silver = "SILVER", bronze = "BRONZE", participant = "PARTICIPANT"

    public init(place: Int) {
        switch place {
        case 1: self = .gold
        case 2: self = .silver
        case 3: self = .bronze
        default: self = .participant
        }
    }

    public var isPodium: Bool { self != .participant }

    public var title: String {
        switch self {
        case .gold: "Золото"
        case .silver: "Серебро"
        case .bronze: "Бронза"
        case .participant: "Медаль участника"
        }
    }
}

public enum TournamentError: Error, Equatable, Sendable {
    case full, notOpen, alreadyRegistered, invalidState, duplicatePlace(Int), notParticipant
}

public struct Tournament: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<Tournament>
    public let organizerId: UserID
    public let clubId: ClubID
    public var title: String
    public var discipline: Discipline
    public var format: TournamentFormat
    public var startsAt: Date
    public var maxParticipants: Int
    public var entryFee: Money?
    public private(set) var status: TournamentStatus
    public private(set) var participantIds: Set<UserID>
    public private(set) var version: Int

    public init(id: ID<Tournament>, organizerId: UserID, clubId: ClubID, title: String,
                discipline: Discipline, format: TournamentFormat, startsAt: Date,
                maxParticipants: Int, entryFee: Money? = nil) {
        self.id = id
        self.organizerId = organizerId
        self.clubId = clubId
        self.title = title
        self.discipline = discipline
        self.format = format
        self.startsAt = startsAt
        self.maxParticipants = maxParticipants
        self.entryFee = entryFee
        self.status = .draft
        self.participantIds = []
        self.version = 0
    }

    public var isFull: Bool { participantIds.count >= maxParticipants }

    public mutating func openRegistration() throws {
        guard status == .draft else { throw TournamentError.invalidState }
        status = .registrationOpen
        version += 1
    }

    public mutating func register(_ studentId: UserID) throws {
        guard status == .registrationOpen else { throw TournamentError.notOpen }
        guard !participantIds.contains(studentId) else { throw TournamentError.alreadyRegistered }
        guard !isFull else { throw TournamentError.full }
        participantIds.insert(studentId)
        version += 1
    }

    public mutating func start() throws {
        guard status == .registrationOpen || status == .registrationClosed else { throw TournamentError.invalidState }
        status = .inProgress
        version += 1
    }

    /// Фиксирует результаты; возвращает список результатов с медалями для начисления наград.
    public mutating func finish(with places: [UserID: Int], recordedAt: Date) throws -> [TournamentResult] {
        guard status == .inProgress else { throw TournamentError.invalidState }
        guard places.keys.allSatisfy({ participantIds.contains($0) }) else { throw TournamentError.notParticipant }

        // Разрешено делить только 3-е место в олимпийской системе (BR-015.3).
        let grouped = Dictionary(grouping: places, by: { $0.value })
        for (place, entries) in grouped where entries.count > 1 {
            let sharedThirdAllowed = place == 3 && format == .singleElimination && entries.count == 2
            if !sharedThirdAllowed { throw TournamentError.duplicatePlace(place) }
        }

        status = .finished
        version += 1
        return places.map { studentId, place in
            TournamentResult(tournamentId: id, studentId: studentId, place: place,
                             medal: Medal(place: place), points: TournamentResult.points(for: place),
                             recordedAt: recordedAt)
        }.sorted { $0.place < $1.place }
    }
}

public struct TournamentResult: Hashable, Codable, Sendable {
    public let tournamentId: ID<Tournament>
    public let studentId: UserID
    public let place: Int
    public let medal: Medal
    public let points: Int
    public let recordedAt: Date

    /// Очки рейтинга клуба за место.
    public static func points(for place: Int) -> Int {
        switch place {
        case 1: 100
        case 2: 70
        case 3: 50
        case 4...8: 25
        default: 10
        }
    }
}
