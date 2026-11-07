// AchievementKit/Sources/AchievementDomain/ProfileCustomization.swift
import Foundation
import CoreDomain

public enum CustomizationItemType: String, Codable, Sendable {
    case frame = "FRAME", badge = "BADGE", title = "TITLE", theme = "THEME", effect = "EFFECT"
}

public struct CustomizationItem: Identifiable, Hashable, Codable, Sendable {

    public init(id: ID<CustomizationItem>, type: CustomizationItemType, code: String, title: String, rarity: Rarity, isAnimated: Bool) {
        self.id = id
        self.type = type
        self.code = code
        self.title = title
        self.rarity = rarity
        self.isAnimated = isAnimated
    }
    public let id: ID<CustomizationItem>
    public let type: CustomizationItemType
    public let code: String          // "frame.gold", "theme.graphite", "effect.aura"
    public let title: String
    public let rarity: Rarity
    public let isAnimated: Bool
}

public enum CustomizationError: Error, Equatable, Sendable {
    case itemLocked(ID<CustomizationItem>)
    case wrongItemType(expected: CustomizationItemType)
}

public struct ProfileCustomization: Hashable, Codable, Sendable {
    public let studentId: UserID
    public private(set) var frame: CustomizationItem?
    public private(set) var badges: [CustomizationItem]
    public private(set) var title: CustomizationItem?
    public private(set) var theme: CustomizationItem?
    public private(set) var effect: CustomizationItem?
    public private(set) var unlockedItemIds: Set<ID<CustomizationItem>>

    public static let maxBadges = 3

    public init(studentId: UserID, unlockedItemIds: Set<ID<CustomizationItem>> = []) {
        self.studentId = studentId
        self.badges = []
        self.unlockedItemIds = unlockedItemIds
    }

    public mutating func unlock(_ itemId: ID<CustomizationItem>) { unlockedItemIds.insert(itemId) }

    public mutating func apply(frame: CustomizationItem?) throws {
        try validate(frame, as: .frame)
        self.frame = frame
    }

    public mutating func apply(title: CustomizationItem?) throws {
        try validate(title, as: .title)
        self.title = title
    }

    public mutating func apply(theme: CustomizationItem?) throws {
        try validate(theme, as: .theme)
        self.theme = theme
    }

    public mutating func apply(effect: CustomizationItem?) throws {
        try validate(effect, as: .effect)
        self.effect = effect
    }

    public mutating func apply(badges: [CustomizationItem]) throws {
        guard badges.count <= Self.maxBadges else { throw DomainValidationError.tooManyBadges(max: Self.maxBadges) }
        try badges.forEach { try validate($0, as: .badge) }
        self.badges = badges
    }

    private func validate(_ item: CustomizationItem?, as type: CustomizationItemType) throws {
        guard let item else { return }
        guard item.type == type else { throw CustomizationError.wrongItemType(expected: type) }
        guard unlockedItemIds.contains(item.id) else { throw CustomizationError.itemLocked(item.id) }
    }
}
