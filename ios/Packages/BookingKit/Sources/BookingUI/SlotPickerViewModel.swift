// BookingKit/Sources/BookingUI/SlotPickerViewModel.swift
import Foundation
import Observation
import CoreDomain
import BookingDomain

@MainActor
@Observable
public final class SlotPickerViewModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded
        case booking
        case booked(Booking)
        case failed(message: String)
    }

    public private(set) var state: State = .idle
    public private(set) var slotsByDay: [Date: [BookingSlot]] = [:]
    public var selectedSlot: BookingSlot?
    public var comment: String = ""

    private let trainerId: UserID
    private let getSlots: GetTrainerSlotsUseCase
    private let createBooking: CreateBookingUseCase
    private let calendar: Calendar
    /// Ключ живёт, пока пользователь не сменит слот: двойной тап не создаст дубликат (AC-005.3).
    private var idempotencyKey = UUID()

    public init(trainerId: UserID, getSlots: GetTrainerSlotsUseCase, createBooking: CreateBookingUseCase,
         calendar: Calendar = .current) {
        self.trainerId = trainerId
        self.getSlots = getSlots
        self.createBooking = createBooking
        self.calendar = calendar
    }

    public func load(period: DateInterval) async {
        state = .loading
        do {
            let slots = try await getSlots.execute(trainerId: trainerId, period: period)
            slotsByDay = Dictionary(grouping: slots) { calendar.startOfDay(for: $0.startsAt) }
            state = .loaded
        } catch {
            state = .failed(message: ErrorPresenter.message(for: error))
        }
    }

    public func select(_ slot: BookingSlot) {
        guard slot.id != selectedSlot?.id else { return }
        selectedSlot = slot
        idempotencyKey = UUID()
    }

    public func book() async {
        guard let slot = selectedSlot, state != .booking else { return }
        state = .booking
        do {
            let booking = try await createBooking.execute(
                slotId: slot.id,
                comment: comment.isEmpty ? nil : comment,
                idempotencyKey: idempotencyKey
            )
            state = .booked(booking)
        } catch BookingError.slotAlreadyTaken {
            state = .failed(message: "Этот слот только что заняли. Выберите другое время.")
            selectedSlot = nil
        } catch {
            state = .failed(message: ErrorPresenter.message(for: error))
        }
    }
}

enum ErrorPresenter {
    static func message(for error: Error) -> String {
        switch error {
        case BookingError.leadTimeViolation(let minutes):
            "Записаться можно не позднее чем за \(minutes / 60) ч до начала."
        case BookingError.pendingLimitExceeded(let limit):
            "У вас уже \(limit) заявки ожидают подтверждения."
        case is URLError:
            "Нет соединения. Проверьте интернет и попробуйте снова."
        default:
            "Что-то пошло не так. Попробуйте ещё раз."
        }
    }
}
