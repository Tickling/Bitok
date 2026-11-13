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
    /// Выбранные слоты: 1–3 подряд (тренировка на 2–3 часа).
    @State private var selectedSlots: [SlotID] = []
    @State private var showConfirm = false
    @State private var openedBooking: BookingRef?
    @State private var openedGroup: GroupRef?

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }
    private var coachId: UserID { container.selectedCoachId }
    private var coach: DemoCoach? { backend.coach(coachId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    coachPicker
                    trainerCard
                    monthHeader
                    MonthGrid(month: month, selection: $selectedDay,
                              availableDays: backend.availableDays(of: coachId, for: me), myBookingDays: myBookingDays)
                    slotsSection
                    groupsSection
                    myBookingsSection
                }
                .padding(Space.l)
                .padding(.bottom, 80)
            }
            .safeAreaInset(edge: .bottom) { continueBar }
            .background(ThemedBackground())
            .navigationTitle("Запись")
            .onChange(of: selectedDay) { _, _ in selectedSlots = [] }
            .onChange(of: container.selectedCoachId) { _, _ in
                selectedSlots = []
                selectedDay = nil
            }
            .sheet(isPresented: $showConfirm) {
                let chosen = selectedSlots.compactMap { backend.slot($0) }.sorted { $0.startsAt < $1.startsAt }
                if let first = chosen.first {
                    BookingConfirmSheet(slots: chosen, container: container) { _ in
                        showConfirm = false
                        selectedSlots = []
                        container.openChat(with: first.trainerId)
                    }
                }
            }
            .sheet(item: $openedBooking) { ref in
                BookingDetailView(bookingId: ref.id, container: container)
            }
            .onAppear {
                // Скриншот «Помощи»: выбран ближайший день и первое время.
                guard container.uiPage == "day", selectedDay == nil,
                      let first = backend.availableDays(of: coachId, for: me).sorted().first(where: {
                          !backend.freeSlots(of: coachId, on: $0, for: me).filter { backend.leadTime($0) > 600 }.isEmpty
                      }) else { return }
                selectedDay = first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    selectedSlots = backend.freeSlots(of: coachId, on: first, for: me).first { backend.leadTime($0) > 600 }.map { [$0.id] } ?? []
                }
            }
            .sheet(item: $openedGroup) { ref in
                GroupSessionSheet(container: container, groupId: ref.id)
            }
        }
    }

    /// Групповые (игровые) тренировки выбранного тренера.
    @ViewBuilder
    private var groupsSection: some View {
        let sessions = backend.openGroups(of: coachId, for: me)
        if !sessions.isEmpty {
            Text("Групповые тренировки").font(.headline)
            ForEach(sessions) { session in
                Button { openedGroup = GroupRef(id: session.id) } label: {
                    GroupCard(session: session, backend: backend, joined: session.participants.contains(me))
                }
                .buttonStyle(.plain)
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
                    withAnimation(.spring(duration: 0.25)) { container.selectedCoachId = item.id }
                } label: {
                    HStack(spacing: Space.xs) {
                        Avatar(initials: item.person.initials, size: 24, userId: item.id)
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
                Avatar(initials: coach.person.initials, size: 44, userId: coach.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.name).font(.headline)
                    Text(coach.rank).font(.caption).foregroundStyle(palette.textSecondary)
                    Label(backend.venues(of: coach.id).filter { backend.canBook(clubId: $0.clubId, student: me) }
                            .map(\.name).joined(separator: " · "), systemImage: "mappin.and.ellipse")
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
            Text(Fmt.monthYear(month))
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
            let slots = backend.freeSlots(of: coachId, on: day, for: me)
            let held = backend.heldSlots(of: coachId, on: day, for: me)
            let manyPlaces = Set(slots.map(\.clubId)).count > 1
            VStack(alignment: .leading, spacing: Space.s) {
                Text(Fmt.day(day)).font(.headline)
                if slots.isEmpty && held.isEmpty {
                    Text("На этот день свободного времени нет").foregroundStyle(palette.textSecondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
                        ForEach((slots + held).sorted { $0.startsAt < $1.startsAt }) { slot in
                            if held.contains(where: { $0.id == slot.id }) {
                                // Уже забронировано другим учеником (ждёт тренера) — неактивно
                                VStack(spacing: 0) {
                                    Text(Fmt.time(slot.startsAt)).font(.callout.weight(.semibold).monospacedDigit()).strikethrough()
                                    Text("забронировано").font(.caption2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(palette.textSecondary)
                                .background(palette.textSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                                .accessibilityLabel("\(Fmt.time(slot.startsAt)), забронировано другим учеником")
                            } else {
                                slotButton(slot, all: slots, manyPlaces: manyPlaces)
                            }
                        }
                    }
                    Text(selectedSlots.count == 1 ? "Нажмите на соседнее время, чтобы взять 2 часа подряд"
                                                  : "Можно выбрать до 3 часов подряд")
                        .font(.caption).foregroundStyle(palette.textSecondary)
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
        let past = all.filter { !$0.status.holdsSlot && $0.status != .rescheduled }.prefix(5)
        let myGroups = backend.groups(ofStudent: me).filter { $0.coachId != coachId }
        if !myGroups.isEmpty {
            Text("Мои групповые у других тренеров").font(.headline)
            ForEach(myGroups) { session in
                Button { openedGroup = GroupRef(id: session.id) } label: {
                    GroupCard(session: session, backend: backend, joined: true)
                }
                .buttonStyle(.plain)
            }
        }
        if !upcoming.isEmpty {
            Text("Мои записи").font(.headline)
            Text("Нажмите на запись, чтобы отменить или перенести").font(.caption).foregroundStyle(palette.textSecondary)
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

    /// Время: нажатие выбирает; соседнее свободное время добавляет час подряд (до 3), нажатие на крайнее — убирает.
    private func slotButton(_ slot: BookingSlot, all: [BookingSlot], manyPlaces: Bool) -> some View {
        let isSelected = selectedSlots.contains(slot.id)
        return Button {
            withAnimation(.spring(duration: 0.25)) { toggle(slot, all: all) }
        } label: {
            VStack(spacing: 0) {
                Text(Fmt.time(slot.startsAt)).font(.callout.weight(.semibold).monospacedDigit())
                if manyPlaces {
                    Text(backend.venue(clubId: slot.clubId)?.name ?? "").font(.caption2).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected ? palette.onAccent : palette.textPrimary)
            .background {
                if isSelected { RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(palette.accent) }
            }
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: Radius.m)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ slot: BookingSlot, all: [BookingSlot]) {
        let chosen = selectedSlots.compactMap { backend.slot($0) }.sorted { $0.startsAt < $1.startsAt }
        if selectedSlots.contains(slot.id) {
            // Убрать можно только крайний час, чтобы оставалось «подряд»
            if slot.id == chosen.first?.id || slot.id == chosen.last?.id { selectedSlots.removeAll { $0 == slot.id } }
            else { selectedSlots = [slot.id] }
            return
        }
        guard let first = chosen.first, let last = chosen.last, chosen.count < 3, slot.clubId == first.clubId else {
            selectedSlots = [slot.id]
            return
        }
        if slot.startsAt == last.endsAt || slot.endsAt == first.startsAt {
            selectedSlots.append(slot.id)
        } else {
            selectedSlots = [slot.id]
        }
    }

    @ViewBuilder
    private var continueBar: some View {
        let chosen = selectedSlots.compactMap { backend.slot($0) }.sorted { $0.startsAt < $1.startsAt }
        if let slot = chosen.first, let last = chosen.last {
            Button("Продолжить · \(Fmt.time(slot.startsAt))–\(Fmt.time(last.endsAt))\(chosen.count > 1 ? " · \(chosen.count) ч" : "")") { showConfirm = true }
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
    /// Один или несколько слотов подряд (тренировка на 2–3 часа).
    let slots: [BookingSlot]
    let container: AppContainer
    let onBooked: (Booking) -> Void
    private var slot: BookingSlot { slots[0] }
    private var minutes: Int { slots.reduce(0) { $0 + $1.durationMinutes } }
    @State private var comment = ""
    @State private var isGroup = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Проверьте запись").font(.title2.weight(.semibold)).fontDesign(palette.headingDesign)
                    VStack(alignment: .leading, spacing: Space.m) {
                        HStack(spacing: Space.m) {
                            Avatar(initials: container.backend.person(slot.trainerId)?.initials ?? "?", size: 44, userId: slot.trainerId)
                            VStack(alignment: .leading) {
                                Text("Тренер").font(.caption).foregroundStyle(palette.textSecondary)
                                Text(container.backend.name(slot.trainerId)).font(.headline)
                            }
                        }
                        Divider()
                        row("calendar", "Дата", Fmt.day(slot.startsAt))
                        row("clock", "Время", Fmt.range(slot.startsAt, minutes: minutes) + (slots.count > 1 ? " · \(slots.count) ч подряд" : ""))
                        row("mappin.and.ellipse", "Где", container.backend.placeTitle(slotId: slot.id))
                        row("building.2", "Адрес", container.backend.placeAddress(slotId: slot.id))
                        row("rublesign.circle", "Стоимость",
                            "\(Fmt.price(Money(amountMinor: container.backend.price(coach: slot.trainerId, student: container.currentUserId).amountMinor * Int64(slots.count), currency: .rub))) · оплата в клубе")
                    }
                    .padding(Space.l)
                    .glassCard()

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Toggle(isOn: $isGroup) {
                            Label("Запись на групповую тренировку", systemImage: "person.3")
                        }
                        Text("Тренер увидит, что вы хотите заниматься в группе (игровая тренировка с другими учениками).")
                            .font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    .padding(Space.m)
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
            var note = isGroup ? "👥 Групповая тренировка" + (text.isEmpty ? "" : ". \(text)") : text
            if slots.count > 1 { note = "\(slots.count) часа подряд" + (note.isEmpty ? "" : ". \(note)") }
            var created: [Booking] = []
            for item in slots {
                let booking = try container.backend.book(slotId: item.id, studentId: container.currentUserId, comment: note.isEmpty ? nil : note)
                if isGroup { container.backend.markGroup(booking.id) }
                created.append(booking)
            }
            if let first = created.first { onBooked(first) }
        } catch {
            errorText = DemoBackend.message(for: error)
        }
    }
}
