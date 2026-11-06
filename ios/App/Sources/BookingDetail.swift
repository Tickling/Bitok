// App/Sources/BookingDetail.swift — карточка тренировки и оценка ученика (общие для ученика и тренера).
import SwiftUI
import UserNotifications
import CoreDomain
import DesignSystem
import BookingDomain
import BookingUI
import ProgressDomain

// MARK: - Общие помощники

struct BookingRef: Identifiable, Hashable {
    let id: BookingID
}

enum Fmt {
    static func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
    static func day(_ date: Date) -> String { date.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
    static func shortDay(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
    static func range(_ start: Date, minutes: Int) -> String {
        "\(time(start))–\(time(start.addingTimeInterval(TimeInterval(minutes * 60))))"
    }
    static func price(_ money: Money) -> String {
        money.decimalValue.formatted(.currency(code: "RUB").precision(.fractionLength(0)))
    }
}

struct Avatar: View {
    @Environment(\.palette) private var palette
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [palette.accent, palette.accentSecondary], startPoint: .topLeading,
                                       endPoint: .bottomTrailing), in: Circle())
            .accessibilityHidden(true)
    }
}

extension View {
    /// Алерт с текстом ошибки; закрытие сбрасывает текст.
    func errorAlert(_ text: Binding<String?>, title: String = "Не получилось") -> some View {
        alert(title, isPresented: Binding(get: { text.wrappedValue != nil }, set: { if !$0 { text.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(text.wrappedValue ?? "")
        }
    }
}

extension BookingStatus {
    func color(in palette: Palette) -> Color {
        switch self {
        case .awaitingCoachApproval, .draft: palette.statusPending
        case .awaitingPayment: palette.statusPayment
        case .confirmed: palette.statusConfirmed
        case .completed: palette.statusCompleted
        default: palette.statusCancelled
        }
    }
}

/// Строка брони в списках.
struct BookingRow: View {
    @Environment(\.palette) private var palette
    let booking: Booking
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: 2).fill(booking.status.color(in: palette)).frame(width: 4)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("\(Fmt.shortDay(booking.startsAt)) · \(Fmt.time(booking.startsAt)) · \(title)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                booking.status.pill
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .glassCard()
        .contentShape(Rectangle())
    }
}

// MARK: - Карточка тренировки

struct BookingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let bookingId: BookingID
    let container: AppContainer
    @State private var errorText: String?
    @State private var infoText: String?
    @State private var showReject = false
    @State private var showCancel = false
    @State private var showEvaluation = false

    private var backend: DemoBackend { container.backend }
    private var isCoach: Bool { container.role == .trainer }

    var body: some View {
        NavigationStack {
            Group {
                if let booking = backend.booking(bookingId) {
                    content(booking)
                } else {
                    ContentUnavailableView("Запись не найдена", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .errorAlert($infoText, title: "Готово")
            .background(ThemedBackground())
            .navigationTitle("Тренировка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
            .navigationDestination(isPresented: $showEvaluation) {
                EvaluationView(bookingId: bookingId, container: container)
            }
            .errorAlert($errorText)
        }
    }

    private func content(_ booking: Booking) -> some View {
        let other = isCoach ? backend.person(booking.studentId) : backend.person(booking.trainerId)
        let coach = backend.coach(booking.trainerId)
        let slot = backend.slot(booking.slotId)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.s) {
                    booking.status.pill
                    Text(Fmt.day(booking.startsAt)).font(.title2.weight(.semibold)).fontDesign(palette.headingDesign)
                    Text(Fmt.range(booking.startsAt, minutes: booking.durationMinutes))
                        .font(.title3.monospacedDigit()).foregroundStyle(palette.textSecondary)
                }

                if let other {
                    HStack(spacing: Space.m) {
                        Avatar(initials: other.initials, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isCoach ? "Ученик" : "Тренер").font(.caption).foregroundStyle(palette.textSecondary)
                            Text(other.name).font(.headline)
                            if let url = URL(string: "tel:\(other.phone.filter { $0.isNumber || $0 == "+" })") {
                                Link(destination: url) { Label(other.phone, systemImage: "phone") }.font(.callout)
                            }
                        }
                        Spacer()
                    }
                    .padding(Space.m)
                    .glassCard()
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    Label("\(coach?.clubName ?? "Клуб"), стол \(slot?.tableNumber ?? 1)", systemImage: "mappin.and.ellipse")
                    Label(coach?.clubAddress ?? "", systemImage: "building.2")
                    Label("\(booking.durationMinutes) мин · \(Fmt.price(booking.price)) · оплата в клубе", systemImage: "rublesign.circle")
                    if let comment = booking.studentComment, !comment.isEmpty {
                        Label("«\(comment)»", systemImage: "text.bubble")
                    }
                }
                .font(.callout)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                if let record = backend.record(for: booking.id) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Оценка тренера").font(.headline)
                        ForEach(MetricKey.allCases) { key in
                            if let value = record.scores.values[key] {
                                HStack {
                                    Text(key.title)
                                    Spacer()
                                    Text("\(value)").monospacedDigit().bold()
                                }
                                .font(.callout)
                            }
                        }
                        if let comment = record.comment {
                            Text("«\(comment)»").font(.callout).foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(Space.m)
                    .glassCard()
                }

                actions(booking)
            }
            .padding(Space.l)
        }
        .confirmationDialog("Причина отказа", isPresented: $showReject, titleVisibility: .visible) {
            ForEach([CancellationReasonCode.scheduleConflict, .coachUnavailable, .clubClosed, .other], id: \.self) { code in
                Button(DemoBackend.reasonTitle(code)) {
                    run { try backend.reject(booking.id, reason: CancellationReason(code: code)) }
                }
            }
        }
        .confirmationDialog("Отменить тренировку?", isPresented: $showCancel, titleVisibility: .visible) {
            Button("Отменить тренировку", role: .destructive) {
                let reason = CancellationReason(code: isCoach ? .coachUnavailable : .scheduleConflict)
                run { try backend.cancel(booking.id, by: container.currentUserId, reason: reason) }
            }
        }
    }

    @ViewBuilder
    private func actions(_ booking: Booking) -> some View {
        let me = container.currentUserId
        let allowed = booking.allowedActions(for: isCoach ? .coach(me) : .student(me), now: Date())
        VStack(spacing: Space.m) {
            if isCoach {
                if allowed.contains(.approve) {
                    Button("Подтвердить заявку") { run { try backend.approve(booking.id) } }
                        .buttonStyle(.cueGlassProminent)
                }
                if allowed.contains(.reject) {
                    Button("Отклонить…", role: .destructive) { showReject = true }.buttonStyle(.bordered)
                }
                if booking.status == .confirmed {
                    Button("Завершить тренировку (демо)") { run { try backend.complete(booking.id) } }
                        .buttonStyle(.cueGlassProminent)
                    Button("Отметить неявку (демо)") { run { try backend.markNoShow(booking.id) } }.buttonStyle(.bordered)
                }
                if booking.status == .completed && !backend.isEvaluated(booking.id) {
                    Button("Оценить ученика") { showEvaluation = true }.buttonStyle(.cueGlassProminent)
                }
                if booking.status == .confirmed && allowed.contains(.cancel) {
                    Button("Отменить тренировку", role: .destructive) { showCancel = true }.buttonStyle(.bordered)
                }
                Button("Написать ученику") {
                    dismiss()
                    container.openChat(with: booking.studentId)
                }
                .buttonStyle(.bordered)
            } else {
                if booking.status.holdsSlot {
                    Button { Task { await addToCalendar(booking) } } label: {
                        Label("Добавить в календарь", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    Button { Task { await remind(booking) } } label: {
                        Label("Напомнить за 2 часа", systemImage: "bell")
                    }
                    .buttonStyle(.bordered)
                }
                if allowed.contains(.cancel) {
                    Button("Отменить запись", role: .destructive) { showCancel = true }.buttonStyle(.bordered)
                }
                Button("Написать тренеру") {
                    dismiss()
                    container.openChat(with: booking.trainerId)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = DemoBackend.message(for: error) }
    }

    private func addToCalendar(_ booking: Booking) async {
        do {
            let sync = EventKitCalendarSync()
            guard try await sync.requestAccess() else {
                errorText = "Нет доступа к календарю. Разрешите его в Настройках → Биток."
                return
            }
            let coach = backend.coach(booking.trainerId)
            try await sync.upsertEvent(for: booking, trainerName: backend.name(booking.trainerId),
                                       clubAddress: "\(coach?.clubName ?? ""), \(coach?.clubAddress ?? "")")
            infoText = "Тренировка добавлена в календарь"
        } catch {
            errorText = "Не удалось добавить в календарь"
        }
    }

    private func remind(_ booking: Booking) async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                errorText = "Уведомления выключены. Разрешите их в Настройках → Биток."
                return
            }
            try await LocalReminderScheduler().schedule(for: booking, minutesBefore: 120)
            infoText = booking.startsAt.addingTimeInterval(-7200) > Date()
                ? "Напомним за 2 часа до тренировки"
                : "До тренировки меньше 2 часов — напоминание не нужно"
        } catch {
            errorText = "Не удалось запланировать напоминание"
        }
    }
}

// MARK: - Оценка ученика (FR-011)

struct EvaluationView: View {
    @Environment(\.dismiss) private var dismiss
    let bookingId: BookingID
    let container: AppContainer
    @State private var scores: [MetricKey: Double] = [:]
    @State private var comment = ""
    @State private var loaded = false
    @State private var errorText: String?

    var body: some View {
        Form {
            if let booking = container.backend.booking(bookingId) {
                Section {
                    LabeledContent("Ученик", value: container.backend.name(booking.studentId))
                    LabeledContent("Тренировка", value: "\(Fmt.shortDay(booking.startsAt)) · \(Fmt.time(booking.startsAt))")
                }
            }
            Section("Навыки, 0–100") {
                ForEach(MetricKey.allCases) { key in
                    VStack(alignment: .leading) {
                        HStack {
                            Label(key.title, systemImage: key.symbolName)
                            Spacer()
                            Text("\(Int(scores[key] ?? 50))").monospacedDigit().bold()
                        }
                        Slider(value: binding(for: key), in: 0...100, step: 1)
                    }
                }
            }
            Section("Комментарий") {
                TextField("Что получилось, над чем поработать", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section {
                Button("Сохранить оценку") { save() }
                    .frame(maxWidth: .infinity)
                    .bold()
            }
        }
        .scrollContentBackground(.hidden)
        .background(ThemedBackground())
        .navigationTitle("Оценка")
        .onAppear(perform: preload)
        .errorAlert($errorText)
    }

    private func binding(for key: MetricKey) -> Binding<Double> {
        Binding(get: { scores[key] ?? 50 }, set: { scores[key] = $0 })
    }

    /// Слайдеры предзаполнены текущими значениями ученика.
    private func preload() {
        guard !loaded, let booking = container.backend.booking(bookingId) else { return }
        let current = container.backend.progress(for: booking.studentId).current
        for key in MetricKey.allCases { scores[key] = Double(current[key] ?? 50) }
        loaded = true
    }

    private func save() {
        do {
            try container.backend.evaluate(bookingId: bookingId,
                                           scores: scores.mapValues { Int($0.rounded()) },
                                           comment: comment.isEmpty ? nil : comment)
            dismiss()
        } catch {
            errorText = DemoBackend.message(for: error)
        }
    }
}
