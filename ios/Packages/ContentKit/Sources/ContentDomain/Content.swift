// ContentKit/Sources/ContentDomain/Content.swift
import Foundation
import CoreDomain

public struct AuthorRef: Hashable, Codable, Sendable {
    public let id: UserID
    public let displayName: String
    public let avatarURL: URL?
}

public enum PublicationStatus: String, Codable, Sendable {
    case draft = "DRAFT", scheduled = "SCHEDULED", published = "PUBLISHED", hidden = "HIDDEN", processing = "PROCESSING"
}

public struct NewsPost: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<NewsPost>
    public let author: AuthorRef
    public let clubId: ClubID?
    public var title: String
    public var body: String           // Markdown-подмножество
    public var imageURLs: [URL]
    public var tags: [String]
    public var status: PublicationStatus
    public var publishedAt: Date?
}

public enum LessonKind: String, Codable, Sendable { case video = "VIDEO", article = "ARTICLE", drill = "DRILL" }

public struct Lesson: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<Lesson>
    public let author: AuthorRef
    public var title: String
    public var summary: String
    public var kind: LessonKind
    public var discipline: Discipline
    public var difficulty: Int        // 1–5
    /// Ключи метрик ProgressKit (stanceAndStroke, aiming, …) — строкой, чтобы не зависеть от ProgressKit.
    public var relatedMetrics: [String]
    public var videoURL: URL?         // HLS
    public var durationSeconds: Int?
}

public protocol ContentRepository: Sendable {
    func news(feed: NewsFeed, cursor: String?) async throws -> Page<NewsPost>
    func lessons(metric: String?, recommended: Bool, cursor: String?) async throws -> Page<Lesson>
}

public enum NewsFeed: String, Sendable { case my = "MY", all = "ALL" }
