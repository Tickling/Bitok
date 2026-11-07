// ProgressKit/Sources/ProgressDomain/ProgressRecord.swift
import Foundation
import CoreDomain

/// Проекция завершённой тренировки (из события BookingCompleted).
public struct CompletedSession: Hashable, Codable, Sendable {
    public let bookingId: BookingID
    public let studentId: UserID
    public let trainerId: UserID
    public let startsAt: Date

    public init(bookingId: BookingID, studentId: UserID, trainerId: UserID, startsAt: Date) {
        self.bookingId = bookingId
        self.studentId = studentId
        self.trainerId = trainerId
        self.startsAt = startsAt
    }
}

public struct ProgressRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<ProgressRecord>
    public let studentId: UserID
    public let trainerId: UserID
    public let bookingId: BookingID
    public var scores: EvaluationScores
    public var comment: String?
    public var recommendations: [String]
    public var assignedLessonIds: [UUID]
    public let evaluatedAt: Date
    public private(set) var revision: Int

    public static let evaluationWindow: TimeInterval = 7 * 24 * 3600
    public static let editWindow: TimeInterval = 24 * 3600

    public init(id: ID<ProgressRecord>, studentId: UserID, trainerId: UserID, bookingId: BookingID,
                scores: EvaluationScores, comment: String?, recommendations: [String],
                assignedLessonIds: [UUID], evaluatedAt: Date, revision: Int = 1) {
        self.id = id
        self.studentId = studentId
        self.trainerId = trainerId
        self.bookingId = bookingId
        self.scores = scores
        self.comment = comment
        self.recommendations = recommendations
        self.assignedLessonIds = assignedLessonIds
        self.evaluatedAt = evaluatedAt
        self.revision = revision
    }

    /// Оценить может только тренер завершённой тренировки в течение 7 дней (BR-011.1).
    /// Progress не зависит от BookingKit: данные о тренировке приходят из события BookingCompleted.
    public static func canEvaluate(session: CompletedSession, by trainerId: UserID, now: Date) -> Bool {
        session.trainerId == trainerId && now.timeIntervalSince(session.startsAt) <= evaluationWindow
    }

    public func canEdit(now: Date) -> Bool { now.timeIntervalSince(evaluatedAt) <= Self.editWindow }
}

/// Агрегат прогресса ученика + журнал изменений метрик.
/// Назван `StudentProgress`, чтобы не конфликтовать с `Foundation.Progress`.
public struct StudentProgress: Hashable, Codable, Sendable {
    public let studentId: UserID
    public private(set) var current: PlayerMetrics
    public private(set) var evaluationsCount: Int
    public private(set) var updatedAt: Date?
    public private(set) var changes: [MetricChange]

    public init(studentId: UserID) {
        self.studentId = studentId
        self.current = PlayerMetrics()
        self.evaluationsCount = 0
        self.changes = []
    }

    public var overallRating: Int? { current.overallRating }

    public mutating func apply(_ record: ProgressRecord) {
        let updated = current.applying(record.scores)
        for key in record.scores.values.keys {
            changes.append(MetricChange(metric: key, oldValue: current[key], newValue: updated[key] ?? 0,
                                        recordId: record.id, changedAt: record.evaluatedAt))
        }
        current = updated
        evaluationsCount += 1
        updatedAt = record.evaluatedAt
    }
}

public struct MetricChange: Hashable, Codable, Sendable {
    public let metric: MetricKey
    public let oldValue: Int?
    public let newValue: Int
    public let recordId: ID<ProgressRecord>
    public let changedAt: Date
}

public struct ProgressSnapshot: Hashable, Codable, Sendable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let metrics: PlayerMetrics

    public init(date: Date, metrics: PlayerMetrics) {
        self.date = date
        self.metrics = metrics
    }
}
