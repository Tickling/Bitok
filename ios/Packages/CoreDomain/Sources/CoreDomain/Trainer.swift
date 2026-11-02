import Foundation

public enum VerificationStatus: String, Codable, Sendable {
    case pendingVerification = "PENDING_VERIFICATION"
    case verified = "VERIFIED"
    case rejected = "REJECTED"
}

public struct Club: Identifiable, Hashable, Codable, Sendable {
    public let id: ClubID
    public var name: String
    public var address: String
    public var timeZoneIdentifier: String

    public init(id: ClubID, name: String, address: String, timeZoneIdentifier: String) {
        self.id = id
        self.name = name
        self.address = address
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

public struct Trainer: Identifiable, Hashable, Codable, Sendable {
    public let id: UserID
    public var displayName: String
    public var avatarURL: URL?
    public var verificationStatus: VerificationStatus
    public var disciplines: Set<Discipline>
    public var clubs: [Club]
    public var rank: String?
    public var experienceYears: Int
    public var bio: String
    public var pricePerHour: Money
    public var rating: Double?
    public var reviewsCount: Int
    public var nextAvailableSlotAt: Date?

    public var canPublishSlots: Bool { verificationStatus == .verified }
}

public struct TrainerBookingSettings: Hashable, Codable, Sendable {
    public var autoConfirm: Bool = false
    public var minLeadTimeMinutes: Int = 120
    public var freeCancellationHours: Int = 12
    public var requiresPrepayment: Bool = false
    public var lateCancellationRefundPercent: Int = 0

    public init() {}
}

public enum SkillLevel: String, Codable, Sendable, CaseIterable {
    case beginner = "BEGINNER", amateur = "AMATEUR", advanced = "ADVANCED", pro = "PRO"
}

public struct Student: Identifiable, Hashable, Codable, Sendable {
    public let id: UserID
    public var displayName: String
    public var avatarURL: URL?
    public var level: SkillLevel
    public var preferredDiscipline: Discipline?
}
