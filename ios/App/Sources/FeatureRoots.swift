// App/Sources/FeatureRoots.swift — корневые экраны вкладок «Прогресс», «Ученики», «Контент», «Профиль».
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
import ShopUI

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
        case progress = "Прогресс", achievements = "Достижения"
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
            Avatar(initials: student.initials, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.name).font(.headline)
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
                    Avatar(initials: student?.initials ?? "?", size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(student?.name ?? "Ученик").font(.title3.weight(.semibold))
                        Text(progress.current.level?.title ?? "Пока без оценок").foregroundStyle(palette.textSecondary)
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

// MARK: - Контент

struct ContentRootView: View {
    let showsShop: Bool

    var body: some View {
        NavigationStack {
            Group {
                if showsShop {
                    ShopComingSoonView()
                } else {
                    ContentUnavailableView("Новости, уроки и турниры", systemImage: "newspaper",
                                           description: Text("Раздел появится в следующей версии"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ThemedBackground())
            .navigationTitle("Контент")
        }
    }
}

// MARK: - Профиль: аккаунт, оформление, демо-настройки

struct ProfileRootView: View {
    @Environment(ThemeManager.self) private var themes
    @Bindable var container: AppContainer
    @State private var confirmReset = false

    var body: some View {
        @Bindable var themeSettings = themes
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfileFrameView(style: container.role == .student ? .gold : nil) {
                            Text(container.backend.person(container.currentUserId)?.initials ?? "?")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                                .frame(width: 96, height: 96)
                                .background(.tint)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                if let account = container.account {
                    Section("Аккаунт") {
                        LabeledContent(account.roleTitle, value: account.displayName)
                        LabeledContent("Телефон", value: account.phone)
                        Button("Выйти") { container.signOut() }
                    }
                }
                Section("Оформление") {
                    Picker("Оформление", selection: $themeSettings.mode) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle("Магазин (shopEnabled)", isOn: $container.flags.shopEnabled)
                    Button("Сбросить демо-данные", role: .destructive) { confirmReset = true }
                } header: {
                    Text("Демо")
                } footer: {
                    Text("Данные общие для всех тестовых учёток на этом телефоне: запишитесь учеником, выйдите и подтвердите заявку тренером.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle("Профиль")
            .confirmationDialog("Удалить все записи, сообщения и оценки и вернуть начальные данные?",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Сбросить", role: .destructive) { container.backend.reset() }
            }
        }
    }
}
