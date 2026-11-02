// ChatKit/Sources/ChatDomain/Chat.swift
import Foundation
import CoreDomain

public enum MessageKind: String, Codable, Sendable {
    case text = "TEXT", image = "IMAGE", system = "SYSTEM", playInvitation = "PLAY_INVITATION"
}

public struct Message: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<Message>
    public let chatId: ID<Chat>
    public let senderId: UserID
    /// Ключ дедупликации при ретраях (BR-017.4).
    public let clientMessageId: UUID
    /// Порядок — по серверному sequence, а не по часам клиента (BR-017.3).
    public let sequence: Int64
    public let kind: MessageKind
    public let text: String?
    public let attachmentURL: URL?
    public var invitation: PlayInvitation?
    public let createdAt: Date
    public var readAt: Date?

    public init(id: ID<Message>, chatId: ID<Chat>, senderId: UserID, clientMessageId: UUID, sequence: Int64,
                kind: MessageKind, text: String?, attachmentURL: URL? = nil, invitation: PlayInvitation? = nil,
                createdAt: Date, readAt: Date? = nil) {
        self.id = id
        self.chatId = chatId
        self.senderId = senderId
        self.clientMessageId = clientMessageId
        self.sequence = sequence
        self.kind = kind
        self.text = text
        self.attachmentURL = attachmentURL
        self.invitation = invitation
        self.createdAt = createdAt
        self.readAt = readAt
    }
}

public struct Chat: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<Chat>
    public let participantIds: [UserID]
    public var lastMessage: Message?
    public var unreadCount: Int

    public init(id: ID<Chat>, participantIds: [UserID], lastMessage: Message? = nil, unreadCount: Int = 0) {
        self.id = id
        self.participantIds = participantIds
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
    }
}

/// Слияние сообщений: дедупликация по clientMessageId, сортировка по sequence.
public func mergeMessages(_ current: [Message], with incoming: [Message]) -> [Message] {
    var byClientId: [UUID: Message] = [:]
    for message in current + incoming { byClientId[message.clientMessageId] = message }
    return byClientId.values.sorted { $0.sequence < $1.sequence }
}

// MARK: - «Предложить поиграть» (BR-017.6)

public enum InvitationType: String, Codable, Sendable { case training = "TRAINING", friendlyGame = "FRIENDLY_GAME" }

public enum InvitationStatus: String, Codable, Sendable {
    case sent = "SENT", accepted = "ACCEPTED", declined = "DECLINED", counterProposed = "COUNTER_PROPOSED", expired = "EXPIRED"
}

public enum InvitationError: Error, Equatable, Sendable { case notRecipient, alreadyAnswered }

public struct PlayInvitation: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<PlayInvitation>
    public let fromId: UserID
    public let toId: UserID
    public let type: InvitationType
    public let clubId: ClubID
    public let proposedAt: Date
    /// Слот тренера: принятие создаёт бронь (FR-028).
    public let slotId: SlotID?
    public var comment: String?
    public private(set) var status: InvitationStatus

    public init(id: ID<PlayInvitation>, fromId: UserID, toId: UserID, type: InvitationType, clubId: ClubID,
                proposedAt: Date, slotId: SlotID? = nil, comment: String? = nil) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.type = type
        self.clubId = clubId
        self.proposedAt = proposedAt
        self.slotId = slotId
        self.comment = comment
        self.status = .sent
    }

    public mutating func answer(by userId: UserID, accept: Bool) throws {
        guard userId == toId else { throw InvitationError.notRecipient }
        guard status == .sent else { throw InvitationError.alreadyAnswered }
        status = accept ? .accepted : .declined
    }
}

// MARK: - «Игроки клуба» (FR-030)

/// Карточка другого ученика. Телефона и email здесь нет по построению (BR-030.2).
public struct PlayerCard: Identifiable, Hashable, Codable, Sendable {
    public let id: UserID
    public let displayName: String
    public let avatarURL: URL?
    public let levelTitle: String          // публичная витрина
    public let specialTitle: String?       // «Чемпион клуба» и т.п.
    public let frameCode: String?          // рамка видна всем
    /// nil — игрок скрыл прогресс (showProgressToStudents = false) → в UI значок 🔒
    public let overallRating: Int?
    /// nil — игрок скрыл достижения
    public let medalsCount: Int?

    public init(id: UserID, displayName: String, avatarURL: URL? = nil, levelTitle: String, specialTitle: String? = nil,
                frameCode: String? = nil, overallRating: Int? = nil, medalsCount: Int? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.levelTitle = levelTitle
        self.specialTitle = specialTitle
        self.frameCode = frameCode
        self.overallRating = overallRating
        self.medalsCount = medalsCount
    }

    public var isProgressHidden: Bool { overallRating == nil }
}

public protocol ChatRepository: Sendable {
    func chats() async throws -> [Chat]
    func messages(chatId: ID<Chat>, afterSequence: Int64?) async throws -> [Message]
    func send(chatId: ID<Chat>, text: String, clientMessageId: UUID) async throws -> Message
    func invite(chatId: ID<Chat>, invitation: PlayInvitation, clientMessageId: UUID) async throws -> Message
    func players(filter: PlayersFilter) async throws -> [PlayerCard]
}

public enum PlayersFilter: String, Sendable { case myClub, myCoachStudents, myLevel }
