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

/// Форматы дат и цен — всегда по-русски, независимо от языка телефона.
enum Fmt {
    static let locale = Locale(identifier: "ru_RU")
    static func time(_ date: Date) -> String { date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().locale(locale)) }
    static func day(_ date: Date) -> String { date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)) }
    static func shortDay(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)) }
    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.standaloneWide).year().locale(locale)).replacingOccurrences(of: " г.", with: "")
    }
    static func stamp(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute().locale(locale))
    }
    static func range(_ start: Date, minutes: Int) -> String {
        "\(time(start))–\(time(start.addingTimeInterval(TimeInterval(minutes * 60))))"
    }
    static func price(_ money: Money) -> String {
        money.decimalValue.formatted(.currency(code: "RUB").precision(.fractionLength(0)).locale(locale))
    }
    static func rubles(_ value: Int64) -> String { price(.rubles(value)) }
}

/// Фото профиля: хранятся на устройстве (Documents/avatars/<id>.jpg). В проде — Media Service + CDN.
@MainActor
@Observable
final class AvatarStore {
    static let shared = AvatarStore()
    private(set) var images: [UserID: UIImage] = [:]

    private var folder: URL {
        URL.documentsDirectory.appending(path: "avatars", directoryHint: .isDirectory)
    }

    private init() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let uuid = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let image = UIImage(contentsOfFile: file.path) else { continue }
            images[UserID(uuid)] = image
        }
    }

    func image(for id: UserID) -> UIImage? { images[id] }

    /// Сохраняет уменьшенную до 512 px копию; nil — удалить фото.
    func set(_ data: Data?, for id: UserID) {
        let file = folder.appending(path: "\(id.rawValue.uuidString).jpg")
        guard let data, let original = UIImage(data: data) else {
            try? FileManager.default.removeItem(at: file)
            images[id] = nil
            return
        }
        let side: CGFloat = 512
        let scale = min(1, side / max(original.size.width, original.size.height))
        let size = CGSize(width: original.size.width * scale, height: original.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? resized.jpegData(compressionQuality: 0.85)?.write(to: file)
        images[id] = resized
    }
}

struct Avatar: View {
    @Environment(\.palette) private var palette
    let initials: String
    var size: CGFloat = 40
    /// Если у пользователя есть фото — показываем его вместо инициалов.
    var userId: UserID? = nil

    var body: some View {
        Group {
            if let userId, let image = AvatarStore.shared.image(for: userId) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(LinearGradient(colors: [palette.accent, palette.accentSecondary], startPoint: .topLeading,
                                               endPoint: .bottomTrailing), in: Circle())
            }
        }
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
    @State private var showSwap = false
    @State private var showCounter = false

    private var backend: DemoBackend { container.backend }
    private var isCoach: Bool { container.role == .trainer }

    /// Текст подтверждения отмены: при отмене позже чем за 12 часов — предупреждение о поздней отмене.
    static func cancelWarning(_ booking: Booking?) -> String {
        guard let booking else { return "" }
        let hours = booking.startsAt.timeIntervalSince(Date()) / 3600
        if booking.status == .confirmed && hours < 12 {
            return "До тренировки меньше 12 часов — отмена будет считаться поздней. Тренер получит уведомление."
        }
        return "Слот освободится, тренер получит уведомление."
    }

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
            .sheet(isPresented: $showCounter) {
                if let booking = backend.booking(bookingId) {
                    ProposeSlotSheet(container: container, studentId: booking.studentId, replacing: bookingId)
                }
            }
            .sheet(isPresented: $showSwap) {
                SwapStudentsSheet(container: container, bookingId: bookingId) { dismiss() }
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
                        Avatar(initials: other.initials, size: 48, userId: other.id)
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
                    Label(backend.placeTitle(slotId: booking.slotId), systemImage: "mappin.and.ellipse")
                    Label(backend.placeAddress(slotId: booking.slotId), systemImage: "building.2")
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
            if isCoach {
                Button("Отменить тренировку", role: .destructive) {
                    run { try backend.cancel(booking.id, by: container.currentUserId, reason: CancellationReason(code: .coachUnavailable)) }
                }
            } else {
                ForEach([CancellationReasonCode.scheduleConflict, .illness, .other], id: \.self) { code in
                    Button(code == .scheduleConflict ? "Изменились планы" : DemoBackend.reasonTitle(code), role: .destructive) {
                        run { try backend.cancel(booking.id, by: container.currentUserId, reason: CancellationReason(code: code)) }
                    }
                }
            }
        } message: {
            Text(Self.cancelWarning(booking))
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
                if booking.status == .awaitingCoachApproval || (booking.status == .confirmed && booking.startsAt > Date()) {
                    Button { showCounter = true } label: {
                        Label("Предложить другое время", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.bordered)
                }
                if !backend.swapCandidates(for: booking.id).isEmpty {
                    Button { showSwap = true } label: {
                        Label("Поменять местами с другим учеником", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
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
                if allowed.contains(.cancel) {
                    Button("Отменить запись", role: .destructive) { showCancel = true }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.statusCancelled)
                    Button {
                        run {
                            try backend.cancel(booking.id, by: me, reason: CancellationReason(code: .scheduleConflict))
                            dismiss()
                            container.openBooking(with: booking.trainerId)
                        }
                    } label: {
                        Label("Перенести на другое время", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                }
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
                                       clubAddress: "\(backend.placeTitle(slotId: booking.slotId)), \(backend.placeAddress(slotId: booking.slotId))")
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

// MARK: - Обмен учеников местами

/// Тренер выбирает, с чьей тренировкой поменять текущую: ученики меняются временем.
struct SwapStudentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let bookingId: BookingID
    var onSwapped: () -> Void = {}
    @State private var selected: BookingID?
    @State private var errorText: String?

    private var backend: DemoBackend { container.backend }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if let source = backend.booking(bookingId) {
                        let candidates = backend.swapCandidates(for: bookingId)
                        Text("\(backend.name(source.studentId)) · \(Fmt.shortDay(source.startsAt)) \(Fmt.time(source.startsAt))")
                            .font(.headline)
                        Text("Выберите, с кем поменять время. Оба ученика получат сообщение в чате, записи останутся подтверждёнными.")
                            .font(.callout).foregroundStyle(palette.textSecondary)
                        if candidates.isEmpty {
                            Text("Нет других подтверждённых тренировок для обмена").foregroundStyle(palette.textSecondary)
                        }
                        ForEach(candidates) { other in
                            Button { selected = other.id } label: {
                                HStack(spacing: Space.m) {
                                    Avatar(initials: backend.person(other.studentId)?.initials ?? "?", size: 40, userId: other.studentId)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(backend.name(other.studentId)).font(.headline)
                                        Text("\(Fmt.shortDay(other.startsAt)) · \(Fmt.time(other.startsAt))")
                                            .font(.callout).foregroundStyle(palette.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: selected == other.id ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(palette.accent)
                                }
                                .padding(Space.m)
                                .glassCard()
                            }
                            .buttonStyle(.plain)
                        }
                        if let selected, let other = backend.booking(selected) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("После обмена").font(.caption).foregroundStyle(palette.textSecondary)
                                Text("\(backend.name(source.studentId)) → \(Fmt.time(other.startsAt))").font(.callout.weight(.semibold))
                                Text("\(backend.name(other.studentId)) → \(Fmt.time(source.startsAt))").font(.callout.weight(.semibold))
                            }
                            .padding(Space.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                            Button("Поменять местами") {
                                do {
                                    try backend.swap(bookingId, with: selected, by: container.currentUserId)
                                    dismiss()
                                    onSwapped()
                                } catch {
                                    errorText = DemoBackend.message(for: error)
                                }
                            }
                            .buttonStyle(.cueGlassProminent)
                        }
                    }
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .navigationTitle("Поменять местами")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .errorAlert($errorText)
        }
    }
}
