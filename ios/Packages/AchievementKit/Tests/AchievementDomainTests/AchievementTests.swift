// AchievementKit/Tests/AchievementDomainTests/AchievementTests.swift
import Testing
import Foundation
import CoreDomain
@testable import AchievementDomain

@Suite("Турниры и медали")
struct TournamentTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let players = (0..<6).map { _ in UserID() }

    func inProgress(format: TournamentFormat = .singleElimination) throws -> Tournament {
        var tournament = Tournament(id: ID(), organizerId: UserID(), clubId: ClubID(), title: "Осенний кубок",
                                    discipline: .russianPyramid, format: format, startsAt: now, maxParticipants: 16)
        try tournament.openRegistration()
        for player in players { try tournament.register(player) }
        try tournament.start()
        return tournament
    }

    @Test("Каждый участник получает медаль: места 1–3 — металл, остальные — медаль участника")
    func everyoneGetsAMedal() throws {
        var tournament = try inProgress()
        let places = Dictionary(uniqueKeysWithValues: players.enumerated().map { ($1, $0 + 1) })
        let results = try tournament.finish(with: places, recordedAt: now)
        #expect(results.map(\.medal) == [.gold, .silver, .bronze, .participant, .participant, .participant])
        #expect(tournament.status == .finished)
    }

    @Test func sharedThirdPlaceAllowedOnlyInSingleElimination() throws {
        var olympic = try inProgress()
        let shared: [UserID: Int] = [players[0]: 1, players[1]: 2, players[2]: 3, players[3]: 3]
        #expect(try olympic.finish(with: shared, recordedAt: now).filter { $0.medal == .bronze }.count == 2)

        var roundRobin = try inProgress(format: .roundRobin)
        #expect(throws: TournamentError.duplicatePlace(3)) { try roundRobin.finish(with: shared, recordedAt: now) }
    }

    @Test func fullTournamentRejectsRegistration() throws {
        var tournament = Tournament(id: ID(), organizerId: UserID(), clubId: ClubID(), title: "Мини",
                                    discipline: .pool, format: .roundRobin, startsAt: now, maxParticipants: 2)
        try tournament.openRegistration()
        try tournament.register(UserID())
        try tournament.register(UserID())
        #expect(throws: TournamentError.full) { try tournament.register(UserID()) }
    }

    @Test("Статистика: шары, победы, соперники, медаль участника")
    func statsRecordsMatches() {
        let me = players[0], rival = players[1]
        let tournamentId = ID<Tournament>()
        var stats = TournamentStats(studentId: me)
        let matches = [
            TournamentMatch(id: ID(), tournamentId: tournamentId, round: 1, playerA: me, playerB: rival,
                            framesA: 3, framesB: 1, ballsPottedA: 31, ballsPottedB: 18),
            TournamentMatch(id: ID(), tournamentId: tournamentId, round: 2, playerA: players[2], playerB: me,
                            framesA: 3, framesB: 2, ballsPottedA: 40, ballsPottedB: 29),
        ]
        let result = TournamentResult(tournamentId: tournamentId, studentId: me, place: 5, medal: Medal(place: 5),
                                      points: TournamentResult.points(for: 5), recordedAt: now)
        stats.record(result: result, matches: matches)
        #expect(stats.medals[.participant] == 1)
        #expect(stats.matchesPlayed == 2 && stats.matchesWon == 1)
        #expect(stats.ballsPotted == 60)
        #expect(stats.opponents[rival]?.wins == 1)
        #expect(stats.winRate == 0.5)
    }
}

@Suite("Уникализация профиля")
struct CustomizationTests {
    let gold = CustomizationItem(id: ID(), type: .frame, code: "frame.gold", title: "Золото", rarity: .legendary, isAnimated: true)

    @Test func lockedItemCannotBeApplied() {
        var customization = ProfileCustomization(studentId: UserID())
        #expect(throws: CustomizationError.itemLocked(gold.id)) { try customization.apply(frame: gold) }
    }

    @Test func unlockedItemApplies() throws {
        var customization = ProfileCustomization(studentId: UserID(), unlockedItemIds: [gold.id])
        try customization.apply(frame: gold)
        #expect(customization.frame == gold)
    }

    @Test func atMostThreeBadges() {
        var customization = ProfileCustomization(studentId: UserID())
        let badges = (0..<4).map { CustomizationItem(id: ID(), type: .badge, code: "b\($0)", title: "B", rarity: .common, isAnimated: false) }
        #expect(throws: DomainValidationError.tooManyBadges(max: 3)) { try customization.apply(badges: badges) }
    }
}
