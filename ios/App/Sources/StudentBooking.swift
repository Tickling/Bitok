// App/Sources/StudentBooking.swift — запись ученика: месяц → день → слот → «Продолжить» → подтверждение → чат.
import SwiftUI
import CoreDomain
import DesignSystem
import BookingDomain
import BookingUI

struct StudentBookingScreen: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var selectedDay: Date?
    @State private var selectedSlotId: SlotID?
    @State private var showConfirm = false
    @State private var openedBooking: BookingRef?
    @State private var coachId: UserID = DemoBackend.alexeyId

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }
    private var coach: DemoCoach? { backend.coach(coachId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    coachPicker
                    trainerCard
                    monthHeader
                    MonthGrid(month: month, selection: $selectedDay,
                              availableDays: backend.availableDays(of: coachId), myBookingDays: myBookingDays)
                    slotsSection
                    myBookingsSection
                }
                .padding(Space.l)
                .padding(.bottom, 80)
            }
            .safeAreaInset(edge: .bottom) { continueBar }
            .background(ThemedBackground())
            .navigationTitle("Запись")
            .onChange(of: selectedDay) { _, _ in selectedSlotId = nil }
            .onChange(of: coachId) { _, _ in
                selectedSlotId = nil
                selectedDay = nil
            }
            .sheet(isPresented: $showConfirm) {
                if let id = selectedSlotId, let slot = backend.slot(id) {
                    BookingConfirmSheet(slot: slot, container: container) { _ in
                        showConfirm = false
                        selectedSlotId = nil
                        container.openChat(with: slot.trainerId)
                    }
                }
            }
            .sheet(item: $openedBooking) { ref in
                BookingDetailView(bookingId: ref.id, container: container)
            }
        }
    }

    private var myBookingDays: Set<Date> {
        Set(backend.bookings(ofStudent: me).filter { $0.status.holdsSlot }
            .map { Calendar.current.startOfDay(for: $0.startsAt) })
    }

    /// Выбор тренера: у каждого свой клуб и своё расписание.
    private var coachPicker: some View {
        HStack(spacing: Space.s) {
            ForEach(backend.coaches) { item in
                let isSelected = item.id == coachId
                Button {
                    withAnimation(.spring(duration: 0.25)) { coachId = item.id }
                } label: {
                    HStack(spacing: Space.xs) {
                        Avatar(initials: item.person.initials, size: 24)
                        Text(item.name.split(separator: " ").first.map(String.init) ?? item.name)
                            .font(.callout.weight(.semibold))
                    }
                    .padding(.vertical, Space.xs)
                    .padding(.leading, Space.xs)
                    .padding(.trailing, Space.m)
                    .foregroundStyle(isSelected ? palette.onAccent : palette.textPrimary)
                    .background(isSelected ? palette.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .glassCard(cornerRadius: 20)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var trainerCard: some View {
        if let coach {
            HStack(spacing: Space.m) {
                Avatar(initials: coach.person.initials, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.name).font(.headline)
                    Text("\(coach.rank) · \(coach.clubName) · \(Fmt.price(coach.price))/ч")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                    Label(coach.scheduleTitle, systemImage: "clock")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(Space.m)
            .glassCard()
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Предыдущий месяц")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()).capitalized)
                .font(.title3.weight(.semibold))
                .fontDesign(palette.headingDesign)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Следующий месяц")
        }
        .padding(.horizontal, Space.s)
    }

    @ViewBuilder
    private var slotsSection: some View {
        if let day = selectedDay {
            let slots = backend.freeSlots(of: coachId, on: day)
            VStack(alignment: .leading, spacing: Space.s) {
                Text(Fmt.day(day).capitalized).font(.headline)
                if slots.isEmpty {
                    Text("На этот день свободного времени нет").foregroundStyle(palette.textSecondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
                        ForEach(slots) { slot in
                            let isSelected = slot.id == selectedSlotId
                            Button {
                                withAnimation(.spring(duration: 0.25)) { selectedSlotId = isSelected ? nil : slot.id }
                            } label: {
                                Text(Fmt.time(slot.startsAt))
                                    .font(.callout.weight(.semibold).monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(isSelected ? palette.onAccent : palette.textPrimary)
                                    .background {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(palette.accent)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .glassCard(cornerRadius: Radius.m)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }
        } else {
            Label("Выберите день — доступные дни выделены", systemImage: "hand.tap")
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var myBookingsSection: some View {
        let all = backend.bookings(ofStudent: me)
        let upcoming = all.filter { $0.status.holdsSlot }.sorted { $0.startsAt < $1.startsAt }
        let past = all.filter { !$0.status.holdsSlot }.prefix(5)
        if !upcoming.isEmpty {
            Text("Мои записи").font(.headline)
            ForEach(upcoming) { booking in
                Button { openedBooking = BookingRef(id: booking.id) } label: {
                    BookingRow(booking: booking, title: backend.name(booking.trainerId))
                }
                .buttonStyle(.plain)
            }
        }
        if !past.isEmpty {
            Text("Прошедшие").font(.headline)
            ForEach(Array(past)) { booking in
                Button { openedBooking = BookingRef(id: booking.id) } label: {
                    BookingRow(booking: booking, title: backend.name(booking.trainerId),
                               subtitle: backend.isEvaluated(booking.id) ? "Есть оценка тренера" : nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var continueBar: some View {
        if let id = selectedSlotId, let slot = backend.slot(id) {
            Button("Продолжить · \(Fmt.time(slot.startsAt))") { showConfirm = true }
                .buttonStyle(.cueGlassProminent)
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.s)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func shiftMonth(_ value: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: value, to: month) else { return }
        month = next
        selectedDay = nil
    }
}

/// Шаг подтверждения записи.
struct BookingConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let slot: BookingSlot
    let container: AppContainer
    let onBooked: (Booking) -> Void
    @State private var comment = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Проверьте запись").font(.title2.weight(.semibold)).fontDesign(palette.headingDesign)
                    VStack(alignment: .leading, spacing: Space.m) {
                        HStack(spacing: Space.m) {
                            Avatar(initials: container.backend.person(slot.trainerId)?.initials ?? "?", size: 44)
                            VStack(alignment: .leading) {
                                Text("Тренер").font(.caption).foregroundStyle(palette.textSecondary)
                                Text(container.backend.name(slot.trainerId)).font(.headline)
                            }
                        }
                        Divider()
                        row("calendar", "Дата", Fmt.day(slot.startsAt).capitalized)
                        row("clock", "Время", Fmt.range(slot.startsAt, minutes: slot.durationMinutes))
                        row("mappin.and.ellipse", "Где", "\(container.backend.coach(slot.trainerId)?.clubName ?? "Клуб"), стол \(slot.tableNumber ?? 1)")
                        row("rublesign.circle", "Стоимость", "\(Fmt.price(slot.price)) · оплата в клубе")
                    }
                    .padding(Space.l)
                    .glassCard()

                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Комментарий тренеру").font(.headline)
                        TextField("Например: хочу поработать над выходом", text: $comment, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(Space.m)
                            .glassCard(cornerRadius: Radius.m)
                    }

                    Label("Тренер подтвердит заявку — статус будет виден в чате с ним", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(Space.l)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Записаться") { book() }
                    .buttonStyle(.cueGlassProminent)
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.s)
            }
            .background(ThemedBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .errorAlert($errorText)
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private func book() {
        do {
            let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            let booking = try container.backend.book(slotId: slot.id, studentId: container.currentUserId,
                                                     comment: text.isEmpty ? nil : text)
            onBooked(booking)
        } catch {
            errorText = DemoBackend.message(for: error)
        }
    }
}
