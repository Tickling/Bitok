// App/Sources/ProfileScreen.swift — профиль как в Telegram: карточка + переходы в подразделы
// («Редактировать профиль», «Трофеи», «Рамка и титул», «Настройки»).
import SwiftUI
import CoreDomain
import DesignSystem
import BookingDomain
import ProgressDomain
import AchievementDomain
import AchievementUI
import PhotosUI

struct ProfileRootView: View {
    @Environment(\.palette) private var palette
    @Bindable var container: AppContainer
    @AppStorage("profile.frame") private var frameCode = FrameChoice.gold.rawValue
    @AppStorage("profile.title") private var titleCode = TitleChoice.champion.rawValue

    @State private var autoPage: String?
    @State private var viewingMyPhoto = false

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    if container.role == .trainer {
                        coachCard
                    } else {
                        playerCard
                        progressBlock
                        nextTrainingCard
                        seasonCard
                        ProfileGiftsGrid(container: container, userId: me)
                    }
                    menu
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .navigationTitle(container.role == .trainer ? "Тренер" : "Игрок")
            .onAppear { autoPage = container.uiPage }
            .fullScreenCover(isPresented: $viewingMyPhoto) { PhotoViewer(userId: me, name: backend.name(me)) }
            .navigationDestination(isPresented: Binding(get: { autoPage == "venues" }, set: { if !$0 { autoPage = nil } })) {
                VenuesView(container: container)
            }
            .navigationDestination(isPresented: Binding(get: { autoPage == "settings" }, set: { if !$0 { autoPage = nil } })) {
                SettingsView(container: container)
            }
        }
    }

    // MARK: - Карточка игрока (ученик)

    private var playerCard: some View {
        let progress = backend.progress(for: me)
        let rating = progress.overallRating ?? 0
        let person = backend.person(me)
        let frame = FrameChoice(rawValue: frameCode) ?? .gold
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(rating)").font(.system(size: 48, weight: .heavy).monospacedDigit())
                    Text((progress.current.level?.title ?? "Новичок").uppercased())
                        .font(.caption.weight(.semibold)).opacity(0.85)
                    Text(person?.name ?? "Игрок").font(.title3.weight(.bold)).padding(.top, Space.s)
                    if let title = TitleChoice(rawValue: titleCode), title != .none {
                        Text("\(title.emoji) \(title.title)").font(.caption).opacity(0.9)
                    }
                }
                Spacer()
                ProfileFrameView(style: frame.style) {
                    Avatar(initials: person?.initials ?? "?", size: 84, userId: me)
                }
                .onTapGesture { if AvatarStore.shared.image(for: me) != nil { viewingMyPhoto = true } }
            }
            HStack {
                ForEach(MetricKey.allCases) { key in
                    VStack(spacing: 2) {
                        Text("\(progress.current[key] ?? 0)").font(.title3.bold().monospacedDigit())
                        Text(Self.short(key)).font(.caption2.weight(.semibold)).opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(Space.l)
        .background(
            LinearGradient(colors: [palette.accent, palette.accent.opacity(0.75), palette.accentSecondary],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: palette.accent.opacity(0.35), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }

    static func short(_ key: MetricKey) -> String {
        switch key {
        case .stanceAndStroke: "МОСТ"
        case .aiming: "СЕР"
        case .positionPlay: "УГОЛ"
        case .cueBallControl: "СИЛА"
        case .tacticalThinking: "ВИНТ"
        }
    }

    @ViewBuilder
    private var nextTrainingCard: some View {
        let next = backend.bookings(ofStudent: me)
            .filter { $0.status.holdsSlot && $0.startsAt > Date() }
            .min { $0.startsAt < $1.startsAt }
        Button {
            container.selectedTab = .calendar
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Следующая тренировка").font(.caption).foregroundStyle(palette.textSecondary)
                    if let next {
                        Text("\(Fmt.shortDay(next.startsAt)) · \(Fmt.time(next.startsAt))").font(.headline)
                        Text("\(backend.name(next.trainerId)) · \(backend.coach(next.trainerId)?.clubName ?? "")")
                            .font(.caption).foregroundStyle(palette.textSecondary)
                    } else {
                        Text("Пока не записаны").font(.headline)
                        Text("Нажмите, чтобы выбрать время").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                if let next {
                    Text(Fmt.time(next.startsAt)).font(.title2.bold().monospacedDigit()).foregroundStyle(palette.accent)
                } else {
                    Image(systemName: "calendar.badge.plus").font(.title2).foregroundStyle(palette.accent)
                }
            }
            .padding(Space.m)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private var seasonCard: some View {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let seasonStart = calendar.date(from: DateComponents(year: year, month: 9, day: 1)) ?? Date()
        let done = backend.bookings(ofStudent: me).filter { $0.status == .completed && $0.startsAt >= seasonStart }.count
        let target = 10
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Сезон «Осень»").font(.headline)
                Text("· \(min(done, target)) / \(target) тренировок").foregroundStyle(palette.textSecondary)
            }
            ProgressView(value: Double(min(done, target)), total: Double(target)).tint(palette.accent)
            Text(done >= target ? "Награда получена: тема «Графит» 🎉" : "Награда: тема профиля «Графит»")
                .font(.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .glassCard()
    }

    // MARK: - Прогресс (у ученика — в профиле, отдельным блоком)

    private var progressBlock: some View {
        let progress = backend.progress(for: me)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Label("Прогресс", systemImage: "chart.line.uptrend.xyaxis").font(.title3.weight(.bold))
                Spacer()
                Text(progress.overallRating.map(String.init) ?? "—").font(.system(size: 30, weight: .heavy).monospacedDigit())
                    .foregroundStyle(palette.accent)
            }
            Text("Уровень: \(progress.current.level?.title ?? "Новичок") · оценки тренера по упражнениям")
                .font(.caption).foregroundStyle(palette.textSecondary)
            ForEach(MetricKey.allCases) { key in
                let value = progress.current[key] ?? 0
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(key.title).font(.caption)
                        Spacer()
                        Text("\(value)").font(.caption.bold().monospacedDigit())
                    }
                    ProgressView(value: Double(value), total: 100).tint(palette.accent)
                }
            }
            HStack(spacing: Space.s) {
                NavigationLink {
                    ProgressRootView(container: container, embedded: true)
                } label: { Text("Подробнее") }
                    .buttonStyle(.cueGlassProminent)
                NavigationLink {
                    ExercisesListView(container: container, studentId: me)
                } label: { Label("Упражнения", systemImage: "list.number") }
                    .buttonStyle(.cueSecondary)
            }
        }
        .padding(Space.l)
        .background(palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.accent.opacity(0.45), lineWidth: 2))
    }

    // MARK: - Карточка тренера

    @ViewBuilder
    private var coachCard: some View {
        if let coach = backend.coach(me) {
            let calendar = Calendar.bitok
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            let weekEnd = weekStart.addingTimeInterval(7 * 86_400)
            let mine = backend.bookings.filter { $0.trainerId == me }
            let thisWeek = mine.filter { $0.status.holdsSlot && $0.startsAt >= weekStart && $0.startsAt < weekEnd }.count
            let waiting = mine.filter { $0.status == .completed && !backend.isEvaluated($0.id) }.count
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    Avatar(initials: backend.person(me)?.initials ?? "?", size: 72, userId: me)
                        .onTapGesture { if AvatarStore.shared.image(for: me) != nil { viewingMyPhoto = true } }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backend.name(me)).font(.title3.weight(.bold))
                        Text(coach.rank).font(.callout).opacity(0.85)
                        Text(backend.venues(of: me).map(\.name).joined(separator: " · ")).font(.caption).opacity(0.85)
                    }
                }
                Label(coach.scheduleTitle, systemImage: "clock").font(.caption).opacity(0.9)
                if !coach.about.isEmpty {
                    Text(coach.about).font(.caption).opacity(0.9)
                }
                HStack {
                    stat("\(backend.students(of: me).count)", "учеников")
                    stat("\(thisWeek)", "на неделе")
                    stat("\(backend.pendingRequests(of: me).count)", "заявок")
                    stat("\(waiting)", "оценить")
                }
            }
            .foregroundStyle(.white)
            .padding(Space.l)
            .background(
                LinearGradient(colors: [palette.accent, palette.accent.opacity(0.75), palette.accentSecondary],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: palette.accent.opacity(0.35), radius: 16, y: 8)
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(caption).font(.caption2).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Меню подразделов

    private var menu: some View {
        VStack(spacing: 0) {
            menuLink("Редактировать профиль", "person.text.rectangle") { EditProfileView(container: container) }
            if container.role == .trainer {
                Divider().padding(.leading, 52)
                menuLink("Места и расписание", "mappin.and.ellipse") { VenuesView(container: container) }
                Divider().padding(.leading, 52)
                menuLink("Групповые тренировки", "person.3") { CoachGroupsView(container: container) }
                Divider().padding(.leading, 52)
                menuLink("Упражнения и уроки", "list.number") { CoachExercisesView(container: container) }
            }
            if container.role == .student {
                Divider().padding(.leading, 52)
                menuLink("Друзья · \(backend.friends(of: me).count)" + (backend.incomingFriendRequests(me).isEmpty ? "" : " · новые запросы"),
                         "person.2") { FriendsView(container: container) }
                Divider().padding(.leading, 52)
                menuLink("Трофеи и достижения", "trophy") {
                    AchievementsScreen(stats: DemoContent.stats(for: me), medalCards: DemoContent.medalCards,
                                       inProgress: [], showToStudents: Binding(
                                           get: { backend.privacy.showAchievementsToStudents },
                                           set: { value in
                                               var settings = backend.privacy
                                               settings.showAchievementsToStudents = value
                                               _ = backend.setPrivacy(settings)
                                           }))
                        .navigationTitle("Трофеи")
                }
                Divider().padding(.leading, 52)
                menuLink("Рамка и титул", "sparkles") { CustomizationView() }
            }
            Divider().padding(.leading, 52)
            menuLink("Настройки", "gearshape") { SettingsView(container: container) }
            Divider().padding(.leading, 52)
            menuLink("Помощь", "questionmark.circle") {
                HelpView(role: container.role, isPro: backend.hasSubscription(me))
            }
        }
        .glassCard()
    }

    private func menuLink<Destination: View>(_ title: String, _ icon: String,
                                             @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 30, height: 30)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Редактировать профиль

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let container: AppContainer
    @State private var profile = DemoProfile(firstName: "", lastName: "", city: "", discipline: "", about: "")
    @State private var coachInfo = DemoCoachInfo(rank: "", scheduleTitle: "", about: "", priceRubles: 0)
    @State private var loaded = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cropping: CropImage?
    @State private var viewingPhoto = false
    @State private var confirmDeletePhoto = false

    private var isCoach: Bool { container.role == .trainer }

    private static let disciplines = ["Русский бильярд", "Пул", "Снукер", "Карамболь"]

    var body: some View {
        Form {
            Section {
                VStack(spacing: Space.s) {
                    // Нажатие на фото открывает просмотр; удаление — только отдельной кнопкой с подтверждением.
                    Button { viewingPhoto = AvatarStore.shared.image(for: container.currentUserId) != nil } label: {
                        Avatar(initials: initials, size: 96, userId: container.currentUserId)
                    }
                    .buttonStyle(.borderless)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(AvatarStore.shared.image(for: container.currentUserId) == nil ? "Загрузить фото" : "Изменить фото",
                              systemImage: "camera")
                    }
                    .buttonStyle(.borderless)
                    if AvatarStore.shared.image(for: container.currentUserId) != nil {
                        Button("Удалить фото", role: .destructive) { confirmDeletePhoto = true }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            if isCoach {
                Section {
                    TextField("Мастер спорта, КМС, тренер по пулу…", text: $coachInfo.rank)
                    TextField("Часы работы, например Пн–Сб 16:00–22:00", text: $coachInfo.scheduleTitle)
                    TextField("Коротко о себе: опыт, специализация", text: $coachInfo.about, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Text("Базовая цена")
                        Spacer()
                        TextField("2500", value: $coachInfo.priceRubles, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("₽")
                    }
                } header: {
                    Text("Тренер")
                } footer: {
                    Text("Цену видит только ученик в своей записи. Для отдельного ученика её можно изменить в его карточке (вкладка «Ученики»).")
                }
            }
            Section("Имя") {
                TextField("Имя", text: $profile.firstName)
                TextField("Фамилия", text: $profile.lastName)
            }
            Section("О себе") {
                TextField("Город", text: $profile.city)
                Picker("Дисциплина", selection: $profile.discipline) {
                    ForEach(Self.disciplines, id: \.self) { Text($0).tag($0) }
                }
                if !isCoach {
                    TextField("Чего хотите добиться", text: $profile.about, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            Section {
                Toggle("Указать дату рождения", isOn: Binding(get: { profile.birthDate != nil },
                                                               set: { profile.birthDate = $0 ? (profile.birthDate ?? Calendar.current.date(byAdding: .year, value: -18, to: Date())) : nil }))
                if let date = profile.birthDate {
                    DatePicker("Дата рождения", selection: Binding(get: { date }, set: { profile.birthDate = $0 }),
                               in: ...Date(), displayedComponents: .date)
                        .environment(\.locale, Fmt.locale)
                    if !isCoach {
                        Picker("Видят другие ученики", selection: Binding(get: { BirthdayVisibility(rawValue: profile.birthdayVisibility ?? "hidden") ?? .hidden },
                                                                         set: { profile.birthdayVisibility = $0.rawValue })) {
                            ForEach(BirthdayVisibility.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }
            } header: {
                Text("День рождения")
            } footer: {
                Text(isCoach ? "Ученики не видят вашу дату рождения." :
                        "По умолчанию другие ученики её не видят. Тренер видит дату всегда, чтобы поздравить. Ученикам младше 14 лет «Биток Про» за полцены.")
            }
            Section("Телефон") {
                Text(container.account?.phone ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(ThemedBackground())
        .navigationTitle("Профиль")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    container.backend.updateProfile(profile, for: container.currentUserId)
                    if isCoach {
                        container.backend.updateCoachInfo(coachInfo, for: container.currentUserId)
                    }
                    dismiss()
                }
                .disabled(profile.firstName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            profile = container.backend.profile(for: container.currentUserId)
            coachInfo = container.backend.coachInfo(for: container.currentUserId)
            loaded = true
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                // Сначала редактор: сдвиг и масштаб, предпросмотр в кружках разного размера.
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    cropping = CropImage(image: image)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $viewingPhoto) {
            PhotoViewer(userId: container.currentUserId, name: container.backend.name(container.currentUserId))
        }
        .confirmationDialog("Удалить фото профиля?", isPresented: $confirmDeletePhoto, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { AvatarStore.shared.set(nil, for: container.currentUserId) }
        }
        .sheet(item: $cropping) { item in
            PhotoCropView(image: item.image) { result in
                AvatarStore.shared.set(result.jpegData(compressionQuality: 0.9), for: container.currentUserId)
            }
        }
    }

    private var initials: String {
        [profile.firstName.first, profile.lastName.first].compactMap { $0 }.map(String.init).joined()
    }
}

// MARK: - Рамка и титул

enum FrameChoice: String, CaseIterable, Identifiable {
    case gold, bronze, steel, none
    var id: Self { self }
    var title: String {
        switch self {
        case .gold: "Золотая"
        case .bronze: "Бронзовая"
        case .steel: "Стальная"
        case .none: "Без рамки"
        }
    }
    var style: FrameStyle? {
        switch self {
        case .gold: .gold
        case .bronze: .bronze
        case .steel: .steel
        case .none: nil
        }
    }
}

enum TitleChoice: String, CaseIterable, Identifiable {
    case champion, sniper, fighter, none
    var id: Self { self }
    var title: String {
        switch self {
        case .champion: "Чемпион клуба"
        case .sniper: "Снайпер"
        case .fighter: "Турнирный боец"
        case .none: "Без титула"
        }
    }
    var emoji: String {
        switch self {
        case .champion: "👑"
        case .sniper: "🎯"
        case .fighter: "🎗"
        case .none: ""
        }
    }
}

struct CustomizationView: View {
    @AppStorage("profile.frame") private var frameCode = FrameChoice.gold.rawValue
    @AppStorage("profile.title") private var titleCode = TitleChoice.champion.rawValue

    var body: some View {
        Form {
            Section("Рамка") {
                Picker("Рамка", selection: $frameCode) {
                    ForEach(FrameChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Picker("Титул", selection: $titleCode) {
                    ForEach(TitleChoice.allCases) { Text("\($0.emoji) \($0.title)").tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Титул")
            } footer: {
                Text("Рамки и титулы открываются медалями и достижениями. «Серебряная», «Графитовая» и «Легенда» появятся после новых турниров.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(ThemedBackground())
        .navigationTitle("Рамка и титул")
    }
}

// MARK: - Настройки

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themes
    @Bindable var container: AppContainer
    @AppStorage("reminder.minutes") private var reminderMinutes = 120
    @AppStorage(LocalNotifier.enabledKey) private var notificationsOn = true
    @AppStorage(TextSize.storageKey) private var textSize = TextSize.standard.rawValue
    @AppStorage("coach.weekGrid") private var weekGrid = true
    @State private var confirmReset = false

    var body: some View {
        @Bindable var themeSettings = themes
        Form {
            Section("Оформление") {
                Picker("Оформление", selection: $themeSettings.mode) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Picker("Размер текста", selection: $textSize) {
                    ForEach(TextSize.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text("Так будет выглядеть текст в приложении")
                    .font(.body)
                    .dynamicTypeSize((TextSize(rawValue: textSize) ?? .standard).dynamicType)
            } header: {
                Text("Текст")
            } footer: {
                Text("Меняет размер текста во всём приложении, независимо от настроек iPhone.")
            }
            if container.role == .trainer {
                Section {
                    Toggle("Сетка недели в календаре", isOn: $weekGrid)
                } header: {
                    Text("Календарь")
                } footer: {
                    Text("Во вкладке «Неделя» — цветная сетка «дни × часы». Выключите, чтобы видеть неделю списком.")
                }
            }
            if container.role == .student {
                Section {
                    Toggle("Показывать прогресс другим ученикам", isOn: privacyBinding(\.showProgressToStudents))
                    Toggle("Показывать достижения другим ученикам", isOn: privacyBinding(\.showAchievementsToStudents))
                    Toggle("Показывать меня в «Учениках»", isOn: privacyBinding(\.discoverableInPlayers))
                    Picker("Дата рождения", selection: Binding(
                        get: { BirthdayVisibility(rawValue: container.backend.profile(for: container.currentUserId).birthdayVisibility ?? "hidden") ?? .hidden },
                        set: { value in
                            var profile = container.backend.profile(for: container.currentUserId)
                            profile.birthdayVisibility = value.rawValue
                            container.backend.updateProfile(profile, for: container.currentUserId)
                        })) {
                        ForEach(BirthdayVisibility.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Приватность")
                } footer: {
                    Text("Ваш тренер видит прогресс всегда. Телефон другим ученикам не показывается никогда.")
                }
            }
            Section {
                Toggle("Уведомления о заявках и сообщениях", isOn: $notificationsOn)
                Picker("Напомнить о тренировке", selection: $reminderMinutes) {
                    Text("За 5 минут").tag(5)
                    Text("За 15 минут").tag(15)
                    Text("За 30 минут").tag(30)
                    Text("За 1 час").tag(60)
                    Text("За 2 часа").tag(120)
                    Text("За 1 день").tag(1440)
                }
            } header: {
                Text("Уведомления")
            } footer: {
                Text("Для проверки: у Алексея есть «Тест-зал 24/7» — слот каждый час, записаться можно за 5 минут до начала. Подтвердите заявку тренером — придёт уведомление и напоминание.")
            }
            Section {
                NavigationLink {
                    AppIconPicker()
                } label: {
                    HStack {
                        Image("IconPreview-\(AppIconOption.all.first { $0.iconName == UIApplication.shared.alternateIconName }?.id ?? "Classic")")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Значок приложения")
                    }
                }
            }
            Section {
                Button("Сбросить демо-данные", role: .destructive) { confirmReset = true }
            } header: {
                Text("Демо")
            } footer: {
                Text("Данные общие для всех тестовых учёток на этом телефоне.")
            }
            if let account = container.account {
                Section("Аккаунт") {
                    LabeledContent(account.roleTitle, value: container.backend.name(container.currentUserId))
                    LabeledContent("Телефон", value: account.phone)
                    Button("Выйти", role: .destructive) { container.signOut() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ThemedBackground())
        .navigationTitle("Настройки")
        .confirmationDialog("Удалить все записи, сообщения и оценки и вернуть начальные данные?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) { container.backend.reset() }
        }
    }

    private func privacyBinding(_ keyPath: WritableKeyPath<PrivacySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { container.backend.privacy[keyPath: keyPath] },
            set: { value in
                var settings = container.backend.privacy
                settings[keyPath: keyPath] = value
                _ = container.backend.setPrivacy(settings)
            }
        )
    }
}

// MARK: - Размер текста

/// Размер текста во всём приложении (применяется в BitokApp через dynamicTypeSize).
enum TextSize: Int, CaseIterable, Identifiable {
    case standard, large, larger, largest
    static let storageKey = "app.textSize"
    var id: Self { self }
    var title: String {
        switch self {
        case .standard: "Стандартный"
        case .large: "Крупный"
        case .larger: "Очень крупный"
        case .largest: "Максимальный"
        }
    }
    var dynamicType: DynamicTypeSize {
        switch self {
        case .standard: .large
        case .large: .xLarge
        case .larger: .xxLarge
        case .largest: .xxxLarge
        }
    }
}

/// Фото, ожидающее обрезки.
struct CropImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Просмотр фото профиля на весь экран (масштаб двумя пальцами).
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let userId: UserID
    let name: String
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = AvatarStore.shared.image(for: userId) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, min(4, $0.magnification)) }
                        .onEnded { _ in withAnimation(.spring) { scale = 1 } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .trailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }
            .padding()
            Text(name).font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 40)
        }
    }
}
