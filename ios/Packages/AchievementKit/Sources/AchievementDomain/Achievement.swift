// AchievementKit/Sources/AchievementDomain/Achievement.swift
import Foundation
import CoreDomain

public enum Rarity: String, Codable, Sendable, CaseIterable, Comparable {
    case common = "COMMON", rare = "RARE", epic = "EPIC", legendary = "LEGENDARY"

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.order < rhs.order }
}

public enum AchievementCategory: String, Codable, Sendable {
    case activity = "ACTIVITY", skill = "SKILL", tournament = "TOURNAMENT", social = "SOCIAL"
}

public struct AchievementDefinition: Identifiable, Hashable, Codable, Sendable {

    public init(code: String, title: String, description: String, rarity: Rarity, category: AchievementCategory, target: Int, rewardItemId: ID<CustomizationItem>?) {
        self.code = code
        self.title = title
        self.description = description
        self.rarity = rarity
        self.category = category
        self.target = target
        self.rewardItemId = rewardItemId
    }
    public var id: String { code }
    public let code: String
    public let title: String
    public let description: String
    public let rarity: Rarity
    public let category: AchievementCategory
    public let target: Int
    public let rewardItemId: ID<CustomizationItem>?
}

public struct Achievement: Identifiable, Hashable, Codable, Sendable {

    public init(id: ID<Achievement>, studentId: UserID, definition: AchievementDefinition, grantedAt: Date, revokedAt: Date? = nil) {
        self.id = id
        self.studentId = studentId
        self.definition = definition
        self.grantedAt = grantedAt
        self.revokedAt = revokedAt
    }
    public let id: ID<Achievement>
    public let studentId: UserID
    public let definition: AchievementDefinition
    public let grantedAt: Date
    public var revokedAt: Date?

    public var isActive: Bool { revokedAt == nil }
}

/// Прогресс к ещё не полученному достижению (7/10).
public struct AchievementProgress: Hashable, Codable, Sendable, Identifiable {

    public init(definition: AchievementDefinition, current: Int) {
        self.definition = definition
        self.current = current
    }
    public var id: String { definition.code }
    public let definition: AchievementDefinition
    public let current: Int

    public var fraction: Double { min(1, Double(current) / Double(max(definition.target, 1))) }
    public var isCompleted: Bool { current >= definition.target }
}
