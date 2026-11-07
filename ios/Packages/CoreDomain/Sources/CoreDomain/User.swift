import Foundation

public enum UserRole: String, Codable, Sendable, CaseIterable {
    case student = "STUDENT"
    case trainer = "TRAINER"
    case clubAdmin = "CLUB_ADMIN"
    case systemAdmin = "SYSTEM_ADMIN"
}

public enum UserStatus: String, Codable, Sendable {
    case active = "ACTIVE", blocked = "BLOCKED", deleted = "DELETED"
}

public enum Discipline: String, Codable, Sendable, CaseIterable {
    case russianPyramid = "RUSSIAN_PYRAMID"
    case pool = "POOL"
    case snooker = "SNOOKER"
    case carom = "CAROM"

    public var localizedTitle: String {
        switch self {
        case .russianPyramid: "Русский бильярд"
        case .pool: "Пул"
        case .snooker: "Снукер"
        case .carom: "Карамболь"
        }
    }
}

public enum DomainValidationError: Error, Equatable, Sendable {
    case invalidPhone
    case invalidName
    case invalidDuration
    case invalidScore(metric: String, value: Int)
    case emptyEvaluation
    case tooManyBadges(max: Int)
    case invalidPlace
}

/// Номер телефона в формате E.164. Хранится в Identity; другим ученикам не показывается никогда (BR-002.2).
public struct PhoneNumber: Hashable, Codable, Sendable {
    public let e164: String

    public init(_ raw: String) throws {
        let digits = raw.filter(\.isNumber)
        let normalized: String
        switch (digits.count, digits.first) {
        case (11, "8"): normalized = "+7" + digits.dropFirst()
        case (11, "7"): normalized = "+" + digits
        case (10, "9"): normalized = "+7" + digits
        default: throw DomainValidationError.invalidPhone
        }
        self.e164 = normalized
    }

    /// Маскированный вид для логов: +7 *** ***-45-67
    public var masked: String {
        "+7 *** ***-\(e164.suffix(4).prefix(2))-\(e164.suffix(2))"
    }
}

public struct User: Identifiable, Hashable, Codable, Sendable {
    public let id: UserID
    public var role: UserRole
    public var firstName: String
    public var lastName: String?
    public var avatarURL: URL?
    public var city: String?
    public var status: UserStatus
    public let createdAt: Date

    public init(id: UserID, role: UserRole, firstName: String, lastName: String? = nil,
                avatarURL: URL? = nil, city: String? = nil, status: UserStatus = .active,
                createdAt: Date) throws {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...50).contains(trimmed.count) else { throw DomainValidationError.invalidName }
        self.id = id
        self.role = role
        self.firstName = trimmed
        self.lastName = lastName
        self.avatarURL = avatarURL
        self.city = city
        self.status = status
        self.createdAt = createdAt
    }

    public var displayName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}
