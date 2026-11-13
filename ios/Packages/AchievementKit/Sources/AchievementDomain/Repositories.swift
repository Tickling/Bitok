// AchievementKit/Sources/AchievementDomain/Repositories.swift
import Foundation
import CoreDomain

public protocol AchievementRepository: Sendable {
    func achievements(studentId: UserID) async throws -> (earned: [Achievement], inProgress: [AchievementProgress])
    func customization(studentId: UserID) async throws -> ProfileCustomization
    func updateCustomization(_ customization: ProfileCustomization) async throws -> ProfileCustomization
}

public protocol TournamentRepository: Sendable {
    func create(_ tournament: Tournament) async throws -> Tournament
    func submitResults(tournamentId: ID<Tournament>, places: [UserID: Int],
                       matches: [TournamentMatch], idempotencyKey: UUID) async throws -> [TournamentResult]
    func stats(studentId: UserID) async throws -> TournamentStats
    func medalCards(studentId: UserID) async throws -> [MedalCard]
}
