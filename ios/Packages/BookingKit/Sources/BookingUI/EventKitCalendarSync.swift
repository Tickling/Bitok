// BookingKit/Sources/BookingUI/EventKitCalendarSync.swift
// Адаптер порта CalendarSyncing (FR-010, раздел 9.2.10).
#if canImport(EventKit)
import EventKit
import Foundation
import CoreDomain
import BookingDomain

/// Связь брони и события: идентификатор хранится локально, а в `EKEvent.url` пишется `bitok://booking/{id}`,
/// чтобы восстановить связь после переустановки или смены eventIdentifier при синхронизации iCloud/Exchange.
public actor EventKitCalendarSync: CalendarSyncing {
    private let store = EKEventStore()
    private let defaults: UserDefaults
    private static let prefix = "calendarEvent."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Запрашивать по нажатию «Добавить в календарь», а не при старте. Только запись (iOS 17+).
    public func requestAccess() async throws -> Bool {
        try await store.requestWriteOnlyAccessToEvents()
    }

    public func upsertEvent(for booking: Booking, trainerName: String, clubAddress: String) async throws {
        let event = existingEvent(for: booking.id) ?? EKEvent(eventStore: store)
        event.calendar = event.calendar ?? store.defaultCalendarForNewEvents
        event.title = "🎱 Тренировка · \(trainerName)"
        event.location = clubAddress
        event.startDate = booking.startsAt
        event.endDate = booking.startsAt.addingTimeInterval(TimeInterval(booking.durationMinutes * 60))
        event.url = URL(string: "bitok://booking/\(booking.id)")
        if event.alarms?.isEmpty ?? true {
            event.addAlarm(EKAlarm(relativeOffset: -3600))
        }
        try store.save(event, span: .thisEvent, commit: true)
        defaults.set(event.eventIdentifier, forKey: Self.prefix + booking.id.description)
    }

    public func removeEvent(for bookingId: BookingID) async throws {
        guard let event = existingEvent(for: bookingId) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
        defaults.removeObject(forKey: Self.prefix + bookingId.description)
    }

    /// Если пользователь удалил событие вручную, `event(withIdentifier:)` вернёт nil —
    /// событие не пересоздаётся автоматически (уважаем выбор пользователя).
    private func existingEvent(for bookingId: BookingID) -> EKEvent? {
        guard let identifier = defaults.string(forKey: Self.prefix + bookingId.description) else { return nil }
        return store.event(withIdentifier: identifier)
    }
}
#endif
