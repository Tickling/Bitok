// App/Sources/FeatureRoots.swift — корневые экраны вкладок «Прогресс» и «Ученики».
// «Контент» — ContentScreens.swift.
// «Профиль» — ProfileScreen.swift.
// «Календарь» — StudentBooking.swift / CoachSchedule.swift, «Чат» — Chat.swift.
import SwiftUI
import CoreDomain
import DesignSystem
import BookingDomain
import BookingUI
import ProgressDomain
import ProgressUI
import AchievementDomain
import AchievementUI

// MARK: - Календарь (по роли)

struct CalendarRootView: View {
    let container: AppContainer

    var body: some View {
        if container.role == .trainer {
            CoachScheduleScreen(container: container)
        } else {
            StudentBookingScreen(container: container)
        }
    }
}

// MARK: - Прогресс + Достижения (ученик)

struct ProgressRootView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case progress = "Прогресс", exercises = "Упражнения", achievements = "Достижения"
        var id: Self { self }
    }

    let container: AppContainer
    @State private var segment: Segment = .progress
    @State private var showAchievements = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Раздел", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Space.l)

                switch segment {
                case .progress:
                    ProgressScreen(viewModel: ProgressViewModel(studentId: container.currentUserId, repository: container.progress))
                        // Новая оценка тренера → экран перечитывает данные.
                        .id(container.backend.records.count)
                case .exercises:
                    ExercisesListView(container: container, studentId: container.currentUserId)
                case .achievements:
                    AchievementsScreen(stats: DemoContent.stats(for: container.currentUserId),
                                       medalCards: DemoContent.medalCards, inProgress: [],
                                       showToStudents: $showAchievements)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(ThemedBackground())
            .navigationTitle(segment.rawValue)
        }
    }
}

// MARK: - Ученики (тренер)

struct StudentsRootView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var query = ""

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.m) {
                    let digits = query.filter(\.isNumber)
                    let students = backend.students(of: me).filter {
                        query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                            || (!digits.isEmpty && $0.phone.filter(\.isNumber).contains(digits))
                    }
                    if students.isEmpty {
                        Text("Учеников пока нет — они появятся после первой записи")
                            .foregroundStyle(palette.textSecondary)
                    }
                    ForEach(students) { student in
                        NavigationLink(value: student.id) { studentRow(student) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .searchable(text: $query, prompt: "Имя или телефон")
            .navigationTitle("Ученики")
            .navigationDestination(for: UserID.self) { id in
                StudentDetailView(container: container, studentId: id)
            }
        }
    }

    private func studentRow(_ student: DemoPerson) -> some View {
        let rating = backend.progress(for: student.id).overallRating
        let waiting = backend.bookings(ofStudent: student.id)
            .contains { $0.trainerId == me && $0.status == .completed && !backend.isEvaluated($0.id) }
        return HStack(spacing: Space.m) {
            Avatar(initials: student.initials, size: 44, userId: student.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.name + (backend.isBirthdayToday(student.id) ? " 🎂" : "")).font(.headline)
                Text(student.phone).font(.caption).foregroundStyle(palette.textSecondary)
                if waiting {
                    Text("✍️ Ждёт оценки").font(.caption.weight(.semibold)).foregroundStyle(palette.statusPending)
                }
            }
            Spacer()
            Text(rating.map(String.init) ?? "—")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(palette.accent)
            Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .glassCard()
    }
}

struct StudentDetailView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    let studentId: UserID
    @State private var openedBooking: BookingRef?

    private var backend: DemoBackend { container.backend }

    var body: some View {
        let student = backend.person(studentId)
        let progress = backend.progress(for: studentId)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.m) {
                    Avatar(initials: student?.initials ?? "?", size: 56, userId: studentId)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(student?.name ?? "Ученик").font(.title3.weight(.semibold))
                        Text(progress.current.level?.title ?? "Пока без оценок").foregroundStyle(palette.textSecondary)
                        if let birthday = backend.birthdayForCoach(of: studentId) {
                            Text((backend.isBirthdayToday(studentId) ? "🎂 Сегодня день рождения! " : "🎂 ") + birthday)
                                .font(.caption.weight(backend.isBirthdayToday(studentId) ? .bold : .regular))
                                .foregroundStyle(backend.isBirthdayToday(studentId) ? palette.accent : palette.textSecondary)
                        }
                        if let phone = student?.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                            Link(destination: url) { Label(phone, systemImage: "phone") }
                        }
                    }
                    Spacer()
                    Text(progress.overallRating.map(String.init) ?? "—")
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.accent)
                }

                // Тренер видит прогресс ученика всегда (FR-013)
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Навыки").font(.headline)
                    ForEach(MetricKey.allCases) { key in
                        let value = progress.current[key] ?? 0
                        VStack(alignment: .leading, spacing: Space.xs) {
                            HStack {
                                Text(key.title)
                                Spacer()
                                Text("\(value)").monospacedDigit().bold()
                            }
                            .font(.callout)
                            ProgressView(value: Double(value), total: 100).tint(palette.accent)
                        }
                    }
                }
                .padding(Space.m)
                .glassCard()

                HStack(spacing: Space.s) {
                    NavigationLink {
                        StudentStatsView(container: container, studentId: studentId)
                    } label: {
                        Label("Статистика и сравнение", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    NavigationLink {
                        ExercisesListView(container: container, studentId: studentId)
                    } label: {
                        Label("Упражнения", systemImage: "list.number").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                StudentPriceCard(container: container, studentId: studentId)

                Button("Написать ученику") { container.openChat(with: studentId) }
                    .buttonStyle(.cueGlassProminent)

                Text("Тренировки").font(.headline)
                ForEach(backend.bookings(ofStudent: studentId).filter { $0.trainerId == container.currentUserId }) { booking in
                    Button { openedBooking = BookingRef(id: booking.id) } label: {
                        BookingRow(booking: booking, title: student?.name ?? "",
                                   subtitle: booking.status == .completed
                                       ? (backend.isEvaluated(booking.id) ? "Оценено" : "Нужно оценить") : nil)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle(student?.name ?? "Ученик")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openedBooking) { ref in
            BookingDetailView(bookingId: ref.id, container: container)
        }
    }
}

/// Индивидуальная цена тренировки для ученика. Применяется к новым записям.
struct StudentPriceCard: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    let studentId: UserID
    @State private var value: Int64 = 0
    @State private var loaded = false

    private var backend: DemoBackend { container.backend }
    private var coachId: UserID { container.currentUserId }

    var body: some View {
        let custom = backend.hasCustomPrice(coach: coachId, student: studentId)
        let base = backend.coach(coachId)?.price ?? .rubles(0)
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Цена для ученика").font(.headline)
                Spacer()
                Text(custom ? "своя" : "базовая").font(.caption.weight(.semibold))
                    .foregroundStyle(custom ? palette.accent : palette.textSecondary)
            }
            HStack {
                TextField("Цена", value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .font(.title3.bold().monospacedDigit())
                    .padding(Space.s)
                    .glassCard(cornerRadius: Radius.m)
                Text("₽ за час").foregroundStyle(palette.textSecondary)
            }
            HStack {
                Button("Сохранить") { backend.setPrice(value, coach: coachId, student: studentId) }
                    .buttonStyle(.borderedProminent)
                if custom {
                    Button("Вернуть базовую (\(Fmt.price(base)))") {
                        backend.setPrice(nil, coach: coachId, student: studentId)
                        value = NSDecimalNumber(decimal: base.decimalValue).int64Value
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.callout)
            Text("Новые записи этого ученика будут по этой цене. Другие ученики её не видят.")
                .font(.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear {
            guard !loaded else { return }
            value = NSDecimalNumber(decimal: backend.price(coach: coachId, student: studentId).decimalValue).int64Value
            loaded = true
        }
    }
}
