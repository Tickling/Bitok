// ProgressKit/Sources/ProgressDomain/PrivacySettings.swift
import Foundation
import CoreDomain

public struct PrivacySettings: Hashable, Codable, Sendable {
    /// «Показывать прогресс другим ученикам». Тренер ученика видит прогресс ВСЕГДА.
    public var showProgressToStudents: Bool = false
    /// «Показывать достижения другим ученикам».
    public var showAchievementsToStudents: Bool = true
    /// Показывать меня в списке «Игроки клуба» (FR-030).
    public var discoverableInPlayers: Bool = true

    public init() {}
}

public enum Viewer: Sendable, Equatable {
    case owner
    case coachOfStudent      // была бронь CONFIRMED/COMPLETED за 12 месяцев
    case otherCoach
    case otherStudent
}

public enum ProtectedData: Sendable {
    case profile, phone, progress, evaluations, achievements
}

/// Матрица доступа FR-013. Источник правды — сервер; на клиенте — для UI-подсказок и тестов.
public enum AccessPolicy {
    public static func canView(_ data: ProtectedData, viewer: Viewer, settings: PrivacySettings) -> Bool {
        switch (data, viewer) {
        case (_, .owner), (_, .coachOfStudent): true
        case (.profile, _): true
        case (.phone, _), (.evaluations, _): false
        case (.progress, .otherStudent): settings.showProgressToStudents
        case (.progress, .otherCoach): false
        case (.achievements, _): settings.showAchievementsToStudents
        }
    }
}
