// App/Sources/DemoData.swift — демо-адаптеры портов (в проде — адаптеры CoreNetwork к BFF).
import Foundation
import CoreDomain
import AchievementDomain
import ChatDomain

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
