// ProgressKit/Sources/ProgressDomain/ProgressRepository.swift
import Foundation
import CoreDomain

public protocol ProgressRepository: Sendable {
    func evaluate(bookingId: BookingID, scores: EvaluationScores, comment: String?,
                  recommendations: [String]) async throws -> ProgressRecord
    func progress(studentId: UserID) async throws -> StudentProgress
    func history(studentId: UserID, from: Date, to: Date) async throws -> [ProgressSnapshot]
    func privacy(studentId: UserID) async throws -> PrivacySettings
    func updatePrivacy(studentId: UserID, _ settings: PrivacySettings) async throws -> PrivacySettings
}
