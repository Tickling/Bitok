// App/Sources/FeatureRoots.swift — корневые экраны вкладок: связывают пакеты фич с демо-данными.
import SwiftUI
import CoreDomain
import DesignSystem
import BookingDomain
import BookingUI
import ProgressDomain
import ProgressUI
import AchievementDomain
import AchievementUI
import ChatDomain
import ShopUI

// MARK: - Календарь

struct CalendarRootView: View {
    let container: AppContainer

    var body: some View {
        NavigationStack {
            if container.role == .trainer {
                CoachCalendarView(entries: Self.demoEntries, onOpenStudent: { _ in }, onCreateSlot: { _ in })
                    .navigationTitle("Сегодня")
            } else {
                StudentCalendarView(
                    viewModel: SlotPickerViewModel(
                        trainerId: container.coachId,
                        getSlots: GetTrainerSlotsInteractor(slots: container.slots),
                        createBooking: CreateBookingInteractor(bookings: container.bookings, slots: container.slots)
                    ),
                    month: Self.currentMonth,
                    myBookingDays: []
                )
            }
        }
    }

    static var currentMonth: DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static var demoEntries: [CoachScheduleEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        func at(_ hour: Int) -> Date { today.addingTimeInterval(TimeInterval(hour * 3600)) }
        return [
            CoachScheduleEntry(id: UUID(), startsAt: at(16), durationMinutes: 60, status: .completed, studentId: UserID(),
                               studentName: "Мария Соколова", studentPhone: "+79165550121"),
            CoachScheduleEntry(id: UUID(), startsAt: at(17), durationMinutes: 60, status: nil, studentId: nil,
                               studentName: nil, studentPhone: nil),
            CoachScheduleEntry(id: UUID(), startsAt: at(18), durationMinutes: 60, status: .awaitingCoachApproval,
                               studentId: UserID(), studentName: "Иван Петров", studentPhone: "+79991234567"),
            CoachScheduleEntry(id: UUID(), startsAt: at(19), durationMinutes: 60, status: .confirmed, studentId: UserID(),
                               studentName: "Олег Морозов", studentPhone: "+79035550102"),
        ]
    }
}

// MARK: - Прогресс + Достижения

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
                case .achievements:
                    AchievementsScreen(stats: DemoContent.stats(for: container.currentUserId),
                                       medalCards: DemoContent.medalCards, inProgress: [],
                                       showToStudents: $showAchievements)
                }
            }
            .background(ThemedBackground())
            .navigationTitle(segment.rawValue)
        }
    }
}

// MARK: - Ученики (тренер)

struct StudentsRootView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(DemoContent.players.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }) { player in
                HStack {
                    VStack(alignment: .leading) {
                        Text(player.displayName).font(.headline)
                        Text(player.levelTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Тренер видит прогресс своих учеников всегда (FR-013)
                    Text("\(player.overallRating ?? 50)").font(.title3.bold().monospacedDigit())
                }
            }
            .searchable(text: $query, prompt: "Имя или телефон")
            .navigationTitle("Ученики")
        }
    }
}

// MARK: - Чат и «Игроки клуба»

struct ChatRootView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case chats = "Чаты", players = "Игроки", notifications = "Уведомления"
        var id: Self { self }
    }

    let role: UserRole
    @State private var segment: Segment = .chats

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Раздел", selection: $segment) {
                    // «Игроки клуба» — только для учеников (FR-030)
                    ForEach(Segment.allCases.filter { role == .student || $0 != .players }) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Space.l)

                switch segment {
                case .chats, .notifications:
                    ContentUnavailableView("Здесь появятся сообщения", systemImage: "bubble.left.and.bubble.right")
                case .players:
                    List(DemoContent.players) { player in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(player.displayName).font(.headline)
                                Text([player.levelTitle, player.specialTitle].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let rating = player.overallRating {
                                Text("\(rating)").font(.title3.bold().monospacedDigit())
                            } else {
                                Image(systemName: "lock.fill").accessibilityLabel("Игрок скрыл прогресс")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Чат")
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
                    ContentUnavailableView("Новости, уроки и турниры", systemImage: "newspaper")
                }
            }
            .navigationTitle("Контент")
        }
    }
}

// MARK: - Профиль: оформление, рамка, приватность, роль

struct ProfileRootView: View {
    @Environment(ThemeManager.self) private var themes
    @Bindable var container: AppContainer

    var body: some View {
        @Bindable var themeSettings = themes
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfileFrameView(style: .gold) {
                            Text("ИП").font(.largeTitle.bold()).frame(width: 96, height: 96).background(.tint)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Оформление") {
                    Picker("Оформление", selection: $themeSettings.mode) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Демо") {
                    Picker("Роль", selection: $container.role) {
                        Text("Ученик").tag(UserRole.student)
                        Text("Тренер").tag(UserRole.trainer)
                    }
                    Toggle("Магазин (shopEnabled)", isOn: $container.flags.shopEnabled)
                }
            }
            .navigationTitle("Профиль")
        }
    }
}
