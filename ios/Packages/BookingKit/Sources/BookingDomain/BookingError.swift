// BookingKit/Sources/BookingDomain/BookingError.swift
import Foundation
import CoreDomain

public enum BookingError: Error, Equatable, Sendable {
    case slotNotAvailable
    case slotAlreadyTaken
    case leadTimeViolation(minimumMinutes: Int)
    case pendingLimitExceeded(limit: Int)
    case overlappingBooking
    case invalidStateTransition(from: BookingStatus, to: BookingStatus)
    case forbidden
    case notCoachesStudent
    case reasonRequired
    case rescheduleLimitExceeded
    case paymentMismatch
    case versionConflict
}
