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
        case group(DemoGroupSession)

        var id: String {
            switch self {
            case .booking(let booking): "b-\(booking.id)"
            case .free(let slot): "s-\(slot.id)"
            case .group(let session): "g-\(session.id)"
            }
        }

        var startsAt: Date {
            switch self {
            case .booking(let booking): booking.startsAt
            case .free(let slot): slot.startsAt
            case .group(let session): session.startsAt
            }
        }
    }

    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var mode: Mode = .day
    @State private var selectedDay: Date? = Calendar.bitok.startOfDay(for: Date())
    @State private var openedBooking: BookingRef?
    @State private var openedGroup: GroupRef?
    @State private var counterBooking: Booking?
    @State private var errorText: String?
    @AppStorage("coach.weekGrid") private var weekGrid = true

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
                        if weekGrid { weekGridView } else { weekView }
                    case .month:
                        MonthGrid(month: day, selection: $selectedDay, availableDays: slotDays, myBookingDays: bookingDays)
                        Text(Fmt.day(day)).font(.headline)
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
            .onAppear {
                switch container.uiPage {
                case "week": mode = .week
                case "tomorrow": selectedDay = Calendar.bitok.date(byAdding: .day, value: 1, to: day)
                default: break
                }
            }
            .sheet(item: $openedGroup) { ref in
                GroupSessionSheet(container: container, groupId: ref.id)
            }
            .sheet(item: $counterBooking) { booking in
                ProposeSlotSheet(container: container, studentId: booking.studentId, replacing: booking.id)
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
                                Avatar(initials: backend.person(booking.studentId)?.initials ?? "?", size: 36, userId: booking.studentId)
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
                        Button { counterBooking = booking } label: {
                            Label("Предложить другое время", systemImage: "calendar.badge.clock")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                    // Нажатие на любое место карточки (кроме кнопок) открывает заявку.
                    .onTapGesture { openedBooking = BookingRef(id: booking.id) }
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
            Text(Calendar.current.isDateInToday(day) ? "Сегодня, \(Fmt.shortDay(day))" : Fmt.day(day))
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
            case .group(let session):
                Button { openedGroup = GroupRef(id: session.id) } label: {
                    GroupCard(session: session, backend: backend)
                }
                .buttonStyle(.plain)
            case .free(let slot):
                Label("\(Fmt.time(slot.startsAt)) · свободно · \(backend.venue(clubId: slot.clubId)?.name ?? "")", systemImage: "plus")
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
                Text(backend.placeTitle(slotId: booking.slotId)).font(.caption).foregroundStyle(palette.textSecondary)
                if backend.isGroupBooking(booking.id) {
                    Label("Хочет в группу", systemImage: "person.3.fill").font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accentSecondary)
                }
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
        let calendar = Calendar.bitok
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
                        Text(Fmt.day(weekDay)).font(.subheadline.weight(.semibold))
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

    // MARK: - Неделя: сетка «дни × часы»

    private enum Cell {
        case booking(Booking), group(DemoGroupSession), free, none
    }

    private func cell(_ day: Date, hour: Int) -> Cell {
        let calendar = Calendar.bitok
        guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return .none }
        let end = start.addingTimeInterval(3600)
        if let session = backend.groups(of: me, on: day).first(where: { $0.startsAt < end && start < $0.endsAt }) {
            return .group(session)
        }
        if let booking = backend.bookings(of: me, on: day).first(where: {
            $0.startsAt < end && start < $0.startsAt.addingTimeInterval(TimeInterval($0.durationMinutes * 60))
                && $0.status != .cancelledByCoach && $0.status != .cancelledByStudent && $0.status != .rejectedByCoach && $0.status != .expired
        }) {
            return .booking(booking)
        }
        if backend.coachFreeSlots(of: me, on: day).contains(where: { $0.startsAt == start }) { return .free }
        return .none
    }

    private var weekGridView: some View {
        let calendar = Calendar.bitok
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let hours = gridHours
        let weekBookings = days.flatMap { backend.bookings(of: me, on: $0) }
        let trainings = weekBookings.filter { $0.status == .confirmed || $0.status == .completed }.count
            + days.flatMap { backend.groups(of: me, on: $0) }.count
        let requests = weekBookings.filter { $0.status == .awaitingCoachApproval }.count
        let toEvaluate = weekBookings.filter { $0.status == .completed && !backend.isEvaluated($0.id) }.count
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Button { shift(days: -7) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text("\(Fmt.shortDay(days.first ?? start)) – \(Fmt.shortDay(days.last ?? start))").font(.headline)
                Spacer()
                Button { shift(days: 7) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal, Space.s)

            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("").frame(width: 34)
                    ForEach(days, id: \.self) { weekDay in
                        Button {
                            selectedDay = weekDay
                            mode = .day
                        } label: {
                            VStack(spacing: 0) {
                                Text(weekDay.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.locale)).capitalizedFirst)
                                    .font(.caption2)
                                Text(weekDay.formatted(.dateTime.day().locale(Fmt.locale))).font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(calendar.isDateInToday(weekDay) ? palette.accent : palette.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(hours, id: \.self) { hour in
                    GridRow {
                        Text(String(format: "%02d", hour)).font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.textSecondary).frame(width: 34)
                        ForEach(days, id: \.self) { weekDay in
                            gridCell(cell(weekDay, hour: hour), day: weekDay)
                        }
                    }
                }
            }
            .padding(Space.s)
            .glassCard()

            HStack(spacing: Space.m) {
                legend(palette.statusConfirmed, "подтв.")
                legend(palette.statusPending, "заявка")
                legend(palette.statusCompleted, "прошла")
                legend(palette.accentSecondary, "группа")
                legend(palette.accent.opacity(0.18), "свободно")
            }
            .font(.caption2)

            Label("Неделя: \(trainings) тренировок · \(requests) заявки · \(toEvaluate) ждут оценки", systemImage: "chart.bar")
                .font(.callout.weight(.semibold))
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            Text("Нажмите на клетку, чтобы открыть тренировку, или на день — чтобы посмотреть его списком.")
                .font(.caption).foregroundStyle(palette.textSecondary)
        }
    }

    /// Часы, в которые у тренера бывают тренировки (по его местам), плюс часы реальных записей.
    private var gridHours: [Int] {
        var hours = Set(backend.venues(of: me).flatMap(\.hours))
        let calendar = Calendar.bitok
        for booking in backend.bookings where booking.trainerId == me {
            hours.insert(calendar.component(.hour, from: booking.startsAt))
        }
        for session in backend.groups(of: me, includePast: true) {
            hours.insert(calendar.component(.hour, from: session.startsAt))
        }
        return hours.isEmpty ? Array(10...21) : Array(hours.min()!...hours.max()!)
    }

    @ViewBuilder
    private func gridCell(_ cell: Cell, day: Date) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        switch cell {
        case .booking(let booking):
            Button { openedBooking = BookingRef(id: booking.id) } label: {
                shape.fill(booking.status.color(in: palette)).frame(height: 26)
                    .overlay {
                        Text(backend.person(booking.studentId)?.initials ?? "")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Fmt.time(booking.startsAt)), \(backend.name(booking.studentId))")
        case .group(let session):
            Button { openedGroup = GroupRef(id: session.id) } label: {
                shape.fill(palette.accentSecondary).frame(height: 26)
                    .overlay { Text("👥").font(.system(size: 10)) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Групповая \(Fmt.time(session.startsAt))")
        case .free:
            Button {
                selectedDay = day
                mode = .day
            } label: {
                shape.fill(palette.accent.opacity(0.18)).frame(height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Свободно")
        case .none:
            shape.fill(palette.textSecondary.opacity(0.06)).frame(height: 26)
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Helpers

    private var slotDays: Set<Date> {
        backend.workingDays(of: me)
    }

    private var bookingDays: Set<Date> {
        Set(backend.bookings.filter { $0.trainerId == me && $0.status.holdsSlot }.map { Calendar.current.startOfDay(for: $0.startsAt) })
            .union(backend.groups(of: me).map { Calendar.current.startOfDay(for: $0.startsAt) })
    }

    private func entries(for day: Date) -> [Entry] {
        (backend.bookings(of: me, on: day).map(Entry.booking) + backend.coachFreeSlots(of: me, on: day).map(Entry.free)
            + backend.groups(of: me, on: day).map(Entry.group))
            .sorted { $0.startsAt < $1.startsAt }
    }

    private func shift(days: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: days, to: day)
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = DemoBackend.message(for: error) }
    }
}
