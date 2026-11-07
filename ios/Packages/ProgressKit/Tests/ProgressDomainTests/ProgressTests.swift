// ProgressKit/Tests/ProgressDomainTests/ProgressTests.swift
import Testing
import Foundation
import CoreDomain
@testable import ProgressDomain

@Suite("Progress & privacy")
struct ProgressTests {
    @Test(arguments: [(score: -1, valid: false), (score: 0, valid: true), (score: 100, valid: true), (score: 101, valid: false)])
    func scoreValidation(score: Int, valid: Bool) {
        let isValid = (try? EvaluationScores([.aiming: score])) != nil
        #expect(isValid == valid)
    }

    @Test func emaSmoothing() throws {
        let metrics = PlayerMetrics(values: [.aiming: 50])
        let updated = metrics.applying(try EvaluationScores([.aiming: 100]))
        #expect(updated[.aiming] == 70) // round(0.4 * 100 + 0.6 * 50)
    }

    @Test func levelTitles() {
        #expect(PlayerLevel(rating: 15) == .novice)
        #expect(PlayerLevel(rating: 80) == .professional)
        #expect(PlayerLevel(rating: 95) == .master)
    }

    @Test func coachAlwaysSeesProgress() {
        var settings = PrivacySettings()
        settings.showProgressToStudents = false
        #expect(AccessPolicy.canView(.progress, viewer: .coachOfStudent, settings: settings))
        #expect(!AccessPolicy.canView(.progress, viewer: .otherStudent, settings: settings))
        #expect(!AccessPolicy.canView(.phone, viewer: .otherStudent, settings: settings))
    }

    @Test func emptyEvaluationRejected() {
        #expect(throws: DomainValidationError.emptyEvaluation) { try EvaluationScores([:]) }
    }

    @Test func historyIsRecorded() throws {
        var progress = StudentProgress(studentId: UserID())
        let record = ProgressRecord(id: ID(), studentId: progress.studentId, trainerId: UserID(), bookingId: BookingID(),
                                    scores: try EvaluationScores([.aiming: 70, .positionPlay: 40]), comment: nil,
                                    recommendations: [], assignedLessonIds: [], evaluatedAt: Date(), revision: 1)
        progress.apply(record)
        #expect(progress.changes.count == 2)
        #expect(progress.overallRating == 55)
    }
}
