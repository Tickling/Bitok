// App/Sources/CoachTools.swift — настройки тренера: места и расписание, групповые тренировки.
import SwiftUI
import CoreDomain
import DesignSystem
import BookingDomain

// MARK: - Места и расписание

/// Список мест тренера: где, когда и для кого он тренирует.
struct VenuesView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var editing: DemoVenue?

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Ученики видят свободное время только в тех местах, которые им открыты. Изменения сразу появляются в их календаре.")
                    .font(.callout)
                    .foregroundStyle(palette.textSecondary)
                ForEach(backend.venues(of: me)) { venue in
                    Button { editing = venue } label: { venueCard(venue) }
                        .buttonStyle(.plain)
                }
                Button {
                    editing = DemoVenue(coachId: me, name: "", address: "", weekdays: [2, 3, 4, 5, 6], hours: [18, 19, 20])
                } label: {
                    Label("Добавить место", systemImage: "plus")
                }
                .buttonStyle(.cueGlassProminent)
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("Места и расписание")
        .sheet(item: $editing) { venue in
            VenueEditor(container: container, venue: venue)
        }
    }

    private func venueCard(_ venue: DemoVenue) -> some View {
        let names = venue.allowedStudents.compactMap { backend.person($0)?.name.split(separator: " ").first.map(String.init) }
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(venue.name).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
            }
            Label(venue.address, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(palette.textSecondary)
            Label("\(venue.daysTitle) · \(venue.hoursTitle)", systemImage: "clock").font(.callout)
            Label(venue.onlySelected ? "Только: \(names.isEmpty ? "никто не выбран" : names.sorted().joined(separator: ", "))"
                                     : "Все ученики",
                  systemImage: venue.onlySelected ? "lock.fill" : "person.3")
                .font(.callout)
                .foregroundStyle(venue.onlySelected ? palette.statusPending : palette.statusConfirmed)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// Редактор места: название, адрес, дни, часы, кто может записаться.
struct VenueEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State var venue: DemoVenue
    @State private var confirmDelete = false

    private var backend: DemoBackend { container.backend }
    private var isNew: Bool { !backend.venues.contains { $0.id == venue.id } }
    private static let allHours = Array(0...23)

    var body: some View {
        NavigationStack {
            Form {
                Section("Место") {
                    TextField("Название, например «Флагман»", text: $venue.name)
                    TextField("Адрес", text: $venue.address)
                }
                Section {
                    HStack(spacing: Space.xs) {
                        ForEach(DemoVenue.weekdayOrder, id: \.self) { weekday in
                            chip(DemoVenue.weekdayTitle(weekday), selected: venue.weekdays.contains(weekday)) {
                                if venue.weekdays.contains(weekday) { venue.weekdays.remove(weekday) } else { venue.weekdays.insert(weekday) }
                            }
                        }
                    }
                } header: {
                    Text("Дни")
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 4), spacing: Space.xs) {
                        ForEach(Self.allHours, id: \.self) { hour in
                            chip(String(format: "%02d:00", hour), selected: venue.hours.contains(hour)) {
                                if let index = venue.hours.firstIndex(of: hour) { venue.hours.remove(at: index) } else { venue.hours.append(hour) }
                            }
                        }
                    }
                } header: {
                    Text("Начало тренировок")
                } footer: {
                    Text("Каждая отмеченная клетка — свободный слот на 1 час в выбранные дни на 3 недели вперёд.")
                }
                Section {
                    Picker("Кто может записаться", selection: $venue.onlySelected) {
                        Text("Все ученики").tag(false)
                        Text("Только выбранные").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if venue.onlySelected {
                        ForEach(backend.students) { student in
                            Button {
                                if venue.allowedStudents.contains(student.id) {
                                    venue.allowedStudents.remove(student.id)
                                } else {
                                    venue.allowedStudents.insert(student.id)
                                }
                            } label: {
                                HStack {
                                    Avatar(initials: student.initials, size: 30, userId: student.id)
                                    Text(student.name).foregroundStyle(palette.textPrimary)
                                    Spacer()
                                    Image(systemName: venue.allowedStudents.contains(student.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(palette.accent)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Доступ")
                } footer: {
                    Text(venue.onlySelected
                         ? "Остальные ученики не увидят это место и его время."
                         : "Время в этом месте видят все ученики.")
                }
                if !isNew {
                    Section {
                        Button("Удалить место", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle(isNew ? "Новое место" : venue.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        backend.saveVenue(venue)
                        dismiss()
                    }
                    .disabled(venue.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Удалить «\(venue.name)»? Свободные слоты исчезнут, записи останутся.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    backend.deleteVenue(venue)
                    dismiss()
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(selected ? palette.onAccent : palette.textPrimary)
                .background(selected ? palette.accent : palette.textSecondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Групповые тренировки (тренер)

struct GroupRef: Identifiable, Hashable { let id: UUID }

struct CoachGroupsView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var creating = false
    @State private var opened: GroupRef?

    private var backend: DemoBackend { container.backend }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Игровые и групповые тренировки: несколько учеников в одно время. Ученики записываются сами в «Календаре».")
                    .font(.callout).foregroundStyle(palette.textSecondary)
                let sessions = backend.groups(of: container.currentUserId)
                if sessions.isEmpty {
                    Text("Пока нет запланированных групповых").foregroundStyle(palette.textSecondary)
                }
                ForEach(sessions) { session in
                    Button { opened = GroupRef(id: session.id) } label: {
                        GroupCard(session: session, backend: backend)
                    }
                    .buttonStyle(.plain)
                }
                Button { creating = true } label: { Label("Создать групповую", systemImage: "plus") }
                    .buttonStyle(.cueGlassProminent)
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("Групповые")
        .sheet(isPresented: $creating) { GroupEditor(container: container) }
        .sheet(item: $opened) { ref in GroupSessionSheet(container: container, groupId: ref.id) }
    }
}

/// Карточка групповой тренировки (общая для тренера и ученика).
struct GroupCard: View {
    @Environment(\.palette) private var palette
    let session: DemoGroupSession
    let backend: DemoBackend
    var joined = false

    var body: some View {
        HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: 2).fill(palette.accentSecondary).frame(width: 4)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("\(Fmt.shortDay(session.startsAt)) · \(Fmt.range(session.startsAt, minutes: session.durationMinutes))")
                    .font(.callout.weight(.semibold))
                Text("👥 \(session.title)").font(.headline)
                Text("\(backend.venue(clubId: session.clubId)?.name ?? "Клуб") · \(Fmt.rubles(session.priceRubles))")
                    .font(.caption).foregroundStyle(palette.textSecondary)
                HStack(spacing: Space.s) {
                    Label("\(session.participants.count) из \(session.capacity)", systemImage: "person.3.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(session.freePlaces == 0 ? palette.statusCancelled : palette.statusConfirmed)
                    if joined {
                        Label("Вы записаны", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(palette.accent)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .glassCard()
    }
}

/// Создание групповой тренировки.
struct GroupEditor: View {
    @Environment(\.dismiss) private var dismiss
    let container: AppContainer
    @State private var title = "Игровая тренировка"
    @State private var clubId: ClubID?
    @State private var date = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()) ?? Date()
    @State private var duration = 120
    @State private var capacity = 6
    @State private var price: Int64 = 1200
    @State private var errorText: String?

    private var backend: DemoBackend { container.backend }

    var body: some View {
        NavigationStack {
            Form {
                Section("Тренировка") {
                    TextField("Название", text: $title)
                    Picker("Место", selection: $clubId) {
                        ForEach(backend.venues(of: container.currentUserId)) { Text($0.name).tag(Optional($0.clubId)) }
                    }
                    DatePicker("Начало", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Fmt.locale)
                    Picker("Длительность", selection: $duration) {
                        Text("1 час").tag(60)
                        Text("1,5 часа").tag(90)
                        Text("2 часа").tag(120)
                        Text("3 часа").tag(180)
                    }
                }
                Section("Участники и цена") {
                    Stepper("Мест: \(capacity)", value: $capacity, in: 2...20)
                    HStack {
                        Text("Цена с человека")
                        Spacer()
                        TextField("1200", value: $price, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("₽")
                    }
                }
                Section {
                    Text("Свободные индивидуальные слоты в это время закроются. Ученики, которым открыто место, получат уведомление.")
                        .font(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle("Новая групповая")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || clubId == nil)
                }
            }
            .onAppear { if clubId == nil { clubId = backend.venues(of: container.currentUserId).first?.clubId } }
            .errorAlert($errorText)
        }
    }

    private func create() {
        guard let clubId else { return }
        do {
            try backend.createGroup(DemoGroupSession(coachId: container.currentUserId, clubId: clubId, title: title,
                                                     startsAt: date, durationMinutes: duration, capacity: capacity,
                                                     priceRubles: price))
            dismiss()
        } catch {
            errorText = DemoBackend.message(for: error)
        }
    }
}

/// Детали групповой: участники; тренер может отменить, ученик — записаться или отказаться.
struct GroupSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let groupId: UUID
    @State private var errorText: String?
    @State private var confirmCancel = false

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let session = backend.group(groupId) {
                    content(session)
                } else {
                    ContentUnavailableView("Тренировка не найдена", systemImage: "person.3")
                }
            }
            .background(ThemedBackground())
            .navigationTitle("Групповая")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .errorAlert($errorText)
        }
    }

    private func content(_ session: DemoGroupSession) -> some View {
        let isCoach = container.role == .trainer
        let joined = session.participants.contains(me)
        let venue = backend.venue(clubId: session.clubId)
        return VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("👥 \(session.title)").font(.title2.weight(.semibold)).fontDesign(palette.headingDesign)
                Text(Fmt.day(session.startsAt)).font(.headline)
                Text(Fmt.range(session.startsAt, minutes: session.durationMinutes)).foregroundStyle(palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Label("Тренер: \(backend.name(session.coachId))", systemImage: "person")
                Label("\(venue?.name ?? "Клуб"), \(venue?.address ?? "")", systemImage: "mappin.and.ellipse")
                Label("\(Fmt.rubles(session.priceRubles)) с человека · оплата в клубе", systemImage: "rublesign.circle")
                Label("Мест: \(session.participants.count) из \(session.capacity)", systemImage: "person.3.fill")
            }
            .font(.callout)
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            if isCoach || joined {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Участники").font(.headline)
                    if session.participants.isEmpty {
                        Text("Пока никто не записался").foregroundStyle(palette.textSecondary)
                    }
                    ForEach(session.participants, id: \.self) { id in
                        HStack {
                            Avatar(initials: backend.person(id)?.initials ?? "?", size: 32, userId: id)
                            Text(id == me ? "Вы" : backend.name(id))
                            Spacer()
                        }
                    }
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }

            if isCoach {
                Button("Отменить групповую", role: .destructive) { confirmCancel = true }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .confirmationDialog("Отменить тренировку? Участники получат сообщение.", isPresented: $confirmCancel,
                                        titleVisibility: .visible) {
                        Button("Отменить", role: .destructive) {
                            backend.cancelGroup(session.id)
                            dismiss()
                        }
                    }
            } else if joined {
                Button("Не смогу прийти", role: .destructive) { backend.leave(group: session.id, student: me) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            } else {
                Button(session.freePlaces > 0 ? "Записаться · \(Fmt.rubles(session.priceRubles))" : "Мест нет") {
                    do { try backend.join(group: session.id, student: me) } catch { errorText = DemoBackend.message(for: error) }
                }
                .buttonStyle(.cueGlassProminent)
                .disabled(session.freePlaces == 0)
            }
        }
        .padding(Space.l)
    }
}
