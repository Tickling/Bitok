// AchievementKit/Sources/AchievementDomain/TournamentStats.swift
import Foundation
import CoreDomain

/// Результат матча турнира (вводит организатор).
public struct TournamentMatch: Identifiable, Hashable, Codable, Sendable {

    public init(id: ID<TournamentMatch>, tournamentId: ID<Tournament>, round: Int, playerA: UserID, playerB: UserID, framesA: Int, framesB: Int, ballsPottedA: Int, ballsPottedB: Int) {
        self.id = id
        self.tournamentId = tournamentId
        self.round = round
        self.playerA = playerA
        self.playerB = playerB
        self.framesA = framesA
        self.framesB = framesB
        self.ballsPottedA = ballsPottedA
        self.ballsPottedB = ballsPottedB
    }
    public let id: ID<TournamentMatch>
    public let tournamentId: ID<Tournament>
    public let round: Int
    public let playerA: UserID
    public let playerB: UserID
    public let framesA: Int
    public let framesB: Int
    public let ballsPottedA: Int
    public let ballsPottedB: Int

    public var winner: UserID { framesA >= framesB ? playerA : playerB }

    public func involves(_ player: UserID) -> Bool { player == playerA || player == playerB }

    public func ballsPotted(by player: UserID) -> Int { player == playerA ? ballsPottedA : ballsPottedB }

    public func opponent(of player: UserID) -> UserID { player == playerA ? playerB : playerA }
}

public struct OpponentRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: UserID { opponentId }
    public let opponentId: UserID
    public var wins: Int
    public var losses: Int
}

/// Статистика турниров ученика (проекция, пересчитывается по TournamentFinished).
public struct TournamentStats: Hashable, Codable, Sendable {
    public let studentId: UserID
    public private(set) var tournamentsPlayed = 0
    public private(set) var medals: [Medal: Int] = [:]
    public private(set) var bestPlace: Int?
    public private(set) var matchesPlayed = 0
    public private(set) var matchesWon = 0
    public private(set) var ballsPotted = 0
    public private(set) var opponents: [UserID: OpponentRecord] = [:]

    public init(studentId: UserID) { self.studentId = studentId }

    public var winRate: Double { matchesPlayed == 0 ? 0 : Double(matchesWon) / Double(matchesPlayed) }
    public var averageBallsPerMatch: Double { matchesPlayed == 0 ? 0 : Double(ballsPotted) / Double(matchesPlayed) }

    /// Чистая функция: добавить итоги одного турнира. Идемпотентность обеспечивает вызывающий
    /// (по `tournamentId` в processed_events).
    public mutating func record(result: TournamentResult, matches: [TournamentMatch]) {
        precondition(result.studentId == studentId)
        tournamentsPlayed += 1
        medals[result.medal, default: 0] += 1
        bestPlace = min(bestPlace ?? result.place, result.place)
        for match in matches where match.involves(studentId) {
            matchesPlayed += 1
            ballsPotted += match.ballsPotted(by: studentId)
            let opponentId = match.opponent(of: studentId)
            var record = opponents[opponentId] ?? OpponentRecord(opponentId: opponentId, wins: 0, losses: 0)
            if match.winner == studentId {
                matchesWon += 1
                record.wins += 1
            } else {
                record.losses += 1
            }
            opponents[opponentId] = record
        }
    }
}

/// Карточка медали: «Первая медаль» с деталями турнира (FR-015, AC-015.5).
public struct MedalCard: Hashable, Sendable, Identifiable {

    public init(tournamentId: ID<Tournament>, tournamentTitle: String, date: Date, clubName: String, place: Int, medal: Medal, matchesWon: Int, matchesPlayed: Int, ballsPotted: Int, defeatedOpponents: [String]) {
        self.tournamentId = tournamentId
        self.tournamentTitle = tournamentTitle
        self.date = date
        self.clubName = clubName
        self.place = place
        self.medal = medal
        self.matchesWon = matchesWon
        self.matchesPlayed = matchesPlayed
        self.ballsPotted = ballsPotted
        self.defeatedOpponents = defeatedOpponents
    }
    public var id: ID<Tournament> { tournamentId }
    public let tournamentId: ID<Tournament>
    public let tournamentTitle: String
    public let date: Date
    public let clubName: String
    public let place: Int
    public let medal: Medal
    public let matchesWon: Int
    public let matchesPlayed: Int
    public let ballsPotted: Int
    public let defeatedOpponents: [String]
}
