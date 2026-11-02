// BookingKit/Sources/BookingUI/LocalReminderScheduler.swift
// Локальное напоминание о тренировке (BR-009.6): работает без сети, по умолчанию за 2 часа.
#if canImport(UserNotifications)
import Foundation
import UserNotifications
import CoreDomain
import BookingDomain

public struct LocalReminderScheduler: ReminderScheduling {
    public init() {}

    public func schedule(for booking: Booking, minutesBefore: Int) async throws {
        let fireDate = booking.startsAt.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Тренировка через \(Self.humanize(minutesBefore))"
        content.body = "Не забудьте кий и мел 🎱"
        content.sound = .default
        content.userInfo = ["bookingId": booking.id.description]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: Self.identifier(booking.id),   // один запрос на бронь — перепланирование заменяет
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    public func cancel(for bookingId: BookingID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier(bookingId)])
    }

    static func identifier(_ id: BookingID) -> String { "booking-\(id)" }

    static func humanize(_ minutes: Int) -> String {
        switch minutes {
        case ..<60: "\(minutes) мин"
        case 60: "1 час"
        case 120: "2 часа"
        case 1440: "1 день"
        default: "\(minutes / 60) ч"
        }
    }
}
#endif
