// App/Sources/CoachSchedule.swift — календарь тренера: новые заявки + день / неделя / месяц.
import SwiftUI
import CoreDomain
import DesignSystem
import BookingDomain
import BookingUI

struct CoachScheduleScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case day = "День", week = "Неделя", month = "Месяц"
        var id: Self { self }
    }

    /// Запись в расписании дня: бронь или свободный слот.
    enum Entry: Identifiable {
        case booking(Booking)
        case free(BookingSlot)

        var id: String {
            switch self {
            case .booking(let booking): "b-\(booking.id)"
            case .free(let slot): "s-\(slot.id)"
            }
        }

        var startsAt: Date {
            switch self {
            case .booking(let booking): booking.startsAt
            case .free(let slot): slot.startsAt
            }
        }
    }

    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var mode: Mode = .day
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: Date())
    @State private var openedBooking: BookingRef?
    @State private var errorText: String?

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }
    private var day: Date { selectedDay ?? Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Picker("Режим", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    requestsSection

                    switch mode {
                    case .day:
                        dayHeader
                        entriesList(for: day)
                    case .week:
                        weekView
                    case .month:
                        MonthGrid(month: day, selection: $selectedDay, availableDays: slotDays, myBookingDays: bookingDays)
                        Text(Fmt.day(day).capitalized).font(.headline)
                        entriesList(for: day)
                    }
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .navigationTitle("Расписание")
            .sheet(item: $openedBooking) { ref in
                BookingDetailView(bookingId: ref.id, container: container)
            }
            .errorAlert($errorText)
        }
    }

    // MARK: - Новые заявки

    @ViewBuilder
    private var requestsSection: some View {
        let requests = backend.pendingRequests(of: me)
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Label("Новые заявки · \(requests.count)", systemImage: "hourglass")
                    .font(.headline)
                    .foregroundStyle(palette.statusPending)
                ForEach(requests) { booking in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Button { openedBooking = BookingRef(id: booking.id) } label: {
                            HStack {
                                Avatar(initials: backend.person(booking.studentId)?.initials ?? "?", size: 36)
                                VStack(alignment: .leading) {
                                    Text(backend.name(booking.studentId)).font(.callout.weight(.semibold))
                                    Text("\(Fmt.shortDay(booking.startsAt)) · \(Fmt.time(booking.startsAt))")
                                        .font(.caption).foregroundStyle(palette.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        HStack {
                            Button("Отклонить") {
                                run { try backend.reject(booking.id, reason: CancellationReason(code: .scheduleConflict)) }
                            }
                            .buttonStyle(.bordered)
                            .tint(palette.statusCancelled)
                            Button("Подтвердить") { run { try backend.approve(booking.id) } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(Space.m)
                    .glassCard()
                }
            }
        }
    }

    // MARK: - День

    private var dayHeader: some View {
        HStack {
            Button { shift(days: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Предыдущий день")
            Spacer()
            Text(Calendar.current.isDateInToday(day) ? "Сегодня, \(Fmt.shortDay(day))" : Fmt.day(day).capitalized)
                .font(.headline)
            Spacer()
            Button { shift(days: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Следующий день")
        }
        .padding(.horizontal, Space.s)
    }

    @ViewBuilder
    private func entriesList(for day: Date) -> some View {
        let items = entries(for: day)
        if items.isEmpty {
            Text("Выходной — слотов нет").foregroundStyle(palette.textSecondary)
        }
        ForEach(items) { entry in
            switch entry {
            case .booking(let booking):
                Button { openedBooking = BookingRef(id: booking.id) } label: {
                    bookingRow(booking)
                }
                .buttonStyle(.plain)
            case .free(let slot):
                Label("\(Fmt.time(slot.startsAt)) · свободно", systemImage: "plus")
                    .font(.callout)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.m)
                    .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                        .strokeBorder(palette.textSecondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
        }
    }

    private func bookingRow(_ booking: Booking) -> some View {
        let student = backend.person(booking.studentId)
        return HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: 2).fill(booking.status.color(in: palette)).frame(width: 4)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("\(Fmt.time(booking.startsAt)) · \(student?.name ?? "Ученик")").font(.headline)
                booking.status.pill
                if let phone = student?.phone {
                    Label(phone, systemImage: "phone").font(.callout).foregroundStyle(palette.accent)
                }
                if booking.status == .completed && !backend.isEvaluated(booking.id) {
                    Text("✍️ Нужно оценить").font(.caption.weight(.semibold)).foregroundStyle(palette.statusPending)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .glassCard()
        .contentShape(Rectangle())
    }

    // MARK: - Неделя

    private var weekView: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        return VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Button { shift(days: -7) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text("\(Fmt.shortDay(days.first ?? start)) – \(Fmt.shortDay(days.last ?? start))").font(.headline)
                Spacer()
                Button { shift(days: 7) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal, Space.s)
            ForEach(days, id: \.self) { weekDay in
                let bookings = backend.bookings(of: me, on: weekDay)
                let free = backend.coachFreeSlots(of: me, on: weekDay).count
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        Text(Fmt.day(weekDay).capitalized).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(free > 0 ? "свободно: \(free)" : "").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    if bookings.isEmpty {
                        Text("Записей нет").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    ForEach(bookings) { booking in
                        Button { openedBooking = BookingRef(id: booking.id) } label: { bookingRow(booking) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var slotDays: Set<Date> {
        backend.workingDays(of: me)
    }

    private var bookingDays: Set<Date> {
        Set(backend.bookings.filter { $0.trainerId == me && $0.status.holdsSlot }.map { Calendar.current.startOfDay(for: $0.startsAt) })
    }

    private func entries(for day: Date) -> [Entry] {
        (backend.bookings(of: me, on: day).map(Entry.booking) + backend.coachFreeSlots(of: me, on: day).map(Entry.free))
            .sorted { $0.startsAt < $1.startsAt }
    }

    private func shift(days: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: days, to: day)
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = DemoBackend.message(for: error) }
    }
}
