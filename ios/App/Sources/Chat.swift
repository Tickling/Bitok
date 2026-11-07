// App/Sources/Chat.swift — чаты, «Игроки клуба», уведомления и диалог с карточками заявок.
import SwiftUI
import CoreDomain
import DesignSystem
import BookingDomain
import BookingUI
import ChatDomain
import ProgressDomain

struct ChatRootView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case chats = "Чаты", players = "Игроки", notifications = "Уведомления"
        var id: Self { self }
    }

    @Environment(\.palette) private var palette
    @Bindable var container: AppContainer
    @State private var segment: Segment = .chats
    @State private var profilePerson: PersonRef?

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        NavigationStack(path: $container.chatPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Picker("Раздел", selection: $segment) {
                        // «Игроки клуба» — только для учеников (FR-030)
                        ForEach(Segment.allCases.filter { container.role == .student || $0 != .players }) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch segment {
                    case .chats: chatsList
                    case .players: playersList
                    case .notifications: notificationsList
                    }
                }
                .padding(Space.l)
            }
            .background(ThemedBackground())
            .navigationTitle("Чат")
            .navigationDestination(for: UserID.self) { otherId in
                ChatThreadView(container: container, otherId: otherId)
            }
            .sheet(item: $profilePerson) { ref in
                PersonProfileSheet(container: container, personId: ref.id)
            }
            .onAppear { if container.uiPage == "players" { segment = .players } }
        }
    }

    private var chatsList: some View {
        ForEach(backend.chatPartners(of: me)) { person in
            NavigationLink(value: person.id) {
                HStack(spacing: Space.m) {
                    Avatar(initials: person.initials, size: 44, userId: person.id)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(person.name).font(.headline)
                            Spacer()
                            if let last = backend.lastMessage(me, person.id) {
                                Text(Fmt.time(last.date)).font(.caption).foregroundStyle(palette.textSecondary)
                            }
                        }
                        Text(backend.lastMessage(me, person.id)?.text ?? (backend.isCoach(person.id) ? "Тренер" : "Ученик"))
                            .font(.callout)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(Space.m)
                .glassCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var playersList: some View {
        ForEach(backend.players(for: me)) { player in
            Button { profilePerson = PersonRef(id: player.id) } label: {
                HStack(spacing: Space.m) {
                    Avatar(initials: player.initials, size: 40, userId: player.id)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name).font(.headline)
                        Text(backend.progress(for: player.id).current.level?.title ?? "Новичок")
                            .font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    if let rating = backend.publicRating(of: player.id) {
                        Text("\(rating)").font(.title3.bold().monospacedDigit()).foregroundStyle(palette.accent)
                    } else {
                        Image(systemName: "lock.fill").foregroundStyle(palette.textSecondary)
                            .accessibilityLabel("Игрок скрыл прогресс")
                    }
                    Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
                }
                .padding(Space.m)
                .glassCard()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var notificationsList: some View {
        let events = backend.events(for: me)
        if events.isEmpty {
            Text("Уведомлений пока нет").foregroundStyle(palette.textSecondary)
        }
        ForEach(events) { event in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.title).font(.callout.weight(.semibold))
                    Spacer()
                    Text(Fmt.stamp(event.date))
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
                Text(event.body).font(.callout).foregroundStyle(palette.textSecondary)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }
}

struct ChatThreadView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    let otherId: UserID
    @State private var draft = ""
    @State private var openedBooking: BookingRef?
    @State private var errorText: String?
    @State private var showPropose = false
    @State private var cancelBooking: BookingRef?
    @State private var showProfile = false
    @State private var swapBooking: BookingRef?
    @State private var counterBooking: BookingRef?

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }
    private var messages: [DemoMessage] { backend.conversation(between: me, and: otherId) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.s) {
                    ForEach(messages) { message in
                        messageView(message).id(message.id)
                    }
                }
                .padding(Space.l)
            }
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy, animated: true) }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .background(ThemedBackground())
        .navigationTitle(backend.name(otherId))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showProfile = true } label: {
                    HStack(spacing: Space.s) {
                        Avatar(initials: backend.person(otherId)?.initials ?? "?", size: 28, userId: otherId)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(backend.name(otherId)).font(.subheadline.weight(.semibold))
                            Text(backend.isCoach(otherId) ? "Тренер · профиль"
                                 : backend.phonesShared(me, otherId) ? (backend.person(otherId)?.phone ?? "") : "Ученик · профиль")
                                .font(.caption2).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Профиль: \(backend.name(otherId))")
            }
        }
        .sheet(isPresented: $showProfile) {
            PersonProfileSheet(container: container, personId: otherId)
        }
        .sheet(item: $openedBooking) { ref in
            BookingDetailView(bookingId: ref.id, container: container)
        }
        .sheet(isPresented: $showPropose) {
            ProposeSlotSheet(container: container, studentId: otherId)
        }
        .sheet(item: $counterBooking) { ref in
            ProposeSlotSheet(container: container, studentId: otherId, replacing: ref.id)
        }
        .sheet(item: $swapBooking) { ref in
            SwapStudentsSheet(container: container, bookingId: ref.id)
        }
        .confirmationDialog("Отменить тренировку?", isPresented: Binding(get: { cancelBooking != nil },
                                                                       set: { if !$0 { cancelBooking = nil } }),
                            titleVisibility: .visible, presenting: cancelBooking) { ref in
            ForEach([CancellationReasonCode.scheduleConflict, .illness, .other], id: \.self) { code in
                Button(code == .scheduleConflict ? "Изменились планы" : DemoBackend.reasonTitle(code), role: .destructive) {
                    run { try backend.cancel(ref.id, by: me, reason: CancellationReason(code: code)) }
                }
            }
        } message: { ref in
            Text(BookingDetailView.cancelWarning(backend.booking(ref.id)))
        }
        .errorAlert($errorText)
    }

    @ViewBuilder
    private func messageView(_ message: DemoMessage) -> some View {
        let mine = message.from == me
        if let request = message.peerRequest {
            peerRequestCard(message: message, request: request)
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        } else if let invitation = message.invitation, let slot = backend.slot(invitation.slotId) {
            invitationCard(message: message, invitation: invitation, slot: slot)
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        } else if let bookingId = message.bookingId, let booking = backend.booking(bookingId) {
            bookingCard(message: message, booking: booking)
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        } else {
            HStack {
                if mine { Spacer(minLength: 48) }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(message.text).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Fmt.time(message.date)).font(.caption2).opacity(0.7)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .foregroundStyle(mine ? palette.onAccent : palette.textPrimary)
                .background {
                    if mine {
                        RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(palette.accent)
                    }
                }
                .glassCard(cornerRadius: Radius.l)
                .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
                if !mine { Spacer(minLength: 48) }
            }
        }
    }

    /// Карточка заявки: статус всегда текущий, у тренера — кнопки подтверждения.
    private func bookingCard(message: DemoMessage, booking: Booking) -> some View {
        let isCoach = container.role == .trainer
        return VStack(alignment: .leading, spacing: Space.s) {
            Text(message.text).font(.callout.weight(.semibold))
            Label("\(Fmt.shortDay(booking.startsAt)) · \(Fmt.range(booking.startsAt, minutes: booking.durationMinutes))",
                  systemImage: "calendar")
                .font(.callout)
            Label(backend.placeTitle(slotId: booking.slotId), systemImage: "mappin.and.ellipse").font(.caption)
                .foregroundStyle(palette.textSecondary)
            booking.status.pill
            if booking.status == .awaitingCoachApproval {
                if isCoach {
                    HStack {
                        Button("Отклонить") {
                            run { try backend.reject(booking.id, reason: CancellationReason(code: .scheduleConflict)) }
                        }
                        .buttonStyle(.bordered)
                        .tint(palette.statusCancelled)
                        Button("Подтвердить") { run { try backend.approve(booking.id) } }
                            .buttonStyle(.borderedProminent)
                    }
                    Button { counterBooking = BookingRef(id: booking.id) } label: {
                        Label("Предложить другое время", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: Space.s) {
                        ProgressView()
                        Text("Ожидает подтверждения тренера").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            HStack {
                Button("Подробнее") { openedBooking = BookingRef(id: booking.id) }.font(.caption)
                Spacer()
                // Тренер может поменять ученика местами с другим (например, Иван 17:00 ↔ Наталья 18:00).
                if isCoach && !backend.swapCandidates(for: booking.id).isEmpty {
                    Button { swapBooking = BookingRef(id: booking.id) } label: {
                        Label("Поменять", systemImage: "arrow.left.arrow.right")
                    }
                    .font(.caption.weight(.semibold))
                }
                // Ученик может отменить запись прямо из чата.
                if !isCoach && booking.allowedActions(for: .student(me), now: Date()).contains(.cancel) {
                    Button("Отменить", role: .destructive) { cancelBooking = BookingRef(id: booking.id) }
                        .font(.caption.weight(.semibold))
                }
            }
            Text(Fmt.time(message.date)).font(.caption2).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .frame(maxWidth: 300, alignment: .leading)
        .glassCard()
    }

    /// Предложение времени от тренера: ученик отвечает одной кнопкой.
    private func invitationCard(message: DemoMessage, invitation: DemoInvitation, slot: BookingSlot) -> some View {
        let isCoach = container.role == .trainer
        return VStack(alignment: .leading, spacing: Space.s) {
            Label("Предложение тренировки", systemImage: "calendar.badge.clock").font(.callout.weight(.semibold))
            Text("\(Fmt.day(slot.startsAt))").font(.callout)
            Text("\(Fmt.range(slot.startsAt, minutes: slot.durationMinutes)) · \(backend.placeTitle(slotId: slot.id))")
                .font(.caption).foregroundStyle(palette.textSecondary)
            if let comment = invitation.comment, !comment.isEmpty {
                Text("«\(comment)»").font(.caption)
            }
            switch invitation.status {
            case .sent:
                if isCoach {
                    HStack(spacing: Space.s) {
                        ProgressView()
                        Text("Ждём ответа ученика").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                } else {
                    HStack(spacing: Space.xs) {
                        Button("Принять") { answer(message, .accept) }.buttonStyle(.borderedProminent)
                        Button("Другое время") { answer(message, .otherTime) }.buttonStyle(.bordered)
                        Button("Нет") { answer(message, .decline) }.buttonStyle(.bordered).tint(palette.statusCancelled)
                    }
                    .font(.caption.weight(.semibold))
                }
            case .accepted:
                Label("Принято — тренировка в календаре", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(palette.statusConfirmed)
                if let bookingId = invitation.bookingId {
                    Button("Подробнее") { openedBooking = BookingRef(id: bookingId) }.font(.caption)
                }
            case .declined:
                Label("Отклонено", systemImage: "xmark.circle").font(.caption).foregroundStyle(palette.statusCancelled)
            case .counterProposed:
                Label("Ученик выбирает другое время", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(palette.textSecondary)
            case .expired:
                Label("Время прошло", systemImage: "clock.badge.xmark").font(.caption).foregroundStyle(palette.textSecondary)
            }
            Text(Fmt.time(message.date)).font(.caption2).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .frame(maxWidth: 300, alignment: .leading)
        .glassCard()
    }

    /// Запрос другого ученика: сыграть или обменяться номерами. Номера появляются только после «Да».
    private func peerRequestCard(message: DemoMessage, request: DemoPeerRequest) -> some View {
        let mine = message.from == me
        let isPlay = request.kind == .playInvite
        return VStack(alignment: .leading, spacing: Space.s) {
            Label(isPlay ? "Приглашение сыграть" : "Обмен номерами",
                  systemImage: isPlay ? "circle.circle" : "phone.arrow.up.right")
                .font(.callout.weight(.semibold))
            Text(message.text).font(.callout)
            switch request.status {
            case .sent:
                if mine {
                    HStack(spacing: Space.s) {
                        ProgressView()
                        Text("Ждём ответа").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                } else {
                    HStack(spacing: Space.s) {
                        Button(isPlay ? "Сыграем!" : "Да, обменяться") {
                            run { try backend.answerPeerRequest(messageId: message.id, by: me, accept: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Нет") {
                            run { try backend.answerPeerRequest(messageId: message.id, by: me, accept: false) }
                        }
                        .buttonStyle(.bordered)
                        .tint(palette.statusCancelled)
                    }
                    .font(.caption.weight(.semibold))
                }
            case .accepted:
                if isPlay {
                    Label("Договорились сыграть ✓", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(palette.statusConfirmed)
                    if !backend.phonesShared(me, otherId) && !backend.hasPendingRequest(.phoneExchange, between: me, and: otherId) {
                        Button {
                            run { try backend.sendPeerRequest(.phoneExchange, from: me, to: otherId) }
                        } label: {
                            Label("Обменяться номерами", systemImage: "phone.arrow.up.right")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption.weight(.semibold))
                    }
                } else {
                    Label("Номера открыты", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(palette.statusConfirmed)
                    ForEach([message.from, message.to], id: \.self) { id in
                        if let person = backend.person(id) {
                            phoneLink(person)
                        }
                    }
                }
            case .declined:
                Label("Отклонено", systemImage: "xmark.circle").font(.caption).foregroundStyle(palette.statusCancelled)
            }
            Text(Fmt.time(message.date)).font(.caption2).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .frame(maxWidth: 300, alignment: .leading)
        .glassCard()
    }

    private func phoneLink(_ person: DemoPerson) -> some View {
        HStack {
            Text(person.id == me ? "Вы" : person.name).font(.caption)
            Spacer()
            if let url = URL(string: "tel:\(person.phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) { Label(person.phone, systemImage: "phone.fill") }.font(.caption.weight(.semibold))
            }
        }
    }

    private func answer(_ message: DemoMessage, _ answer: DemoBackend.InvitationAnswer) {
        run {
            try backend.answerInvitation(messageId: message.id, by: me, answer)
            if answer == .otherTime { container.openBooking(with: message.from) }
        }
    }

    private var composer: some View {
        HStack(spacing: Space.s) {
            // Тренер предлагает своё время; ученик переходит к записи к этому тренеру.
            if container.role == .trainer || backend.isCoach(otherId) {
                Button {
                    if container.role == .trainer {
                        showPropose = true
                    } else {
                        container.openBooking(with: otherId)
                    }
                } label: {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 24))
                }
                .accessibilityLabel(container.role == .trainer ? "Предложить время" : "Записаться к тренеру")
            } else if container.role == .student {
                // Ученик ↔ ученик: пригласить сыграть или предложить обменяться номерами.
                Menu {
                    Button {
                        run { try backend.sendPeerRequest(.playInvite, from: me, to: otherId) }
                    } label: {
                        Label("Предложить сыграть", systemImage: "circle.circle")
                    }
                    .disabled(backend.hasPendingRequest(.playInvite, between: me, and: otherId))
                    if !backend.phonesShared(me, otherId) {
                        Button {
                            run { try backend.sendPeerRequest(.phoneExchange, from: me, to: otherId) }
                        } label: {
                            Label("Обменяться номерами", systemImage: "phone.arrow.up.right")
                        }
                        .disabled(backend.hasPendingRequest(.phoneExchange, between: me, and: otherId))
                    }
                } label: {
                    Image(systemName: "plus.circle").font(.system(size: 26))
                }
                .accessibilityLabel("Предложить сыграть или обменяться номерами")
            }
            TextField("Сообщение", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .glassCard(cornerRadius: 22)
            Button {
                backend.send(from: me, to: otherId, text: draft)
                draft = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = messages.last?.id else { return }
        if animated {
            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorText = DemoBackend.message(for: error) }
    }
}

/// Тренер выбирает свой свободный слот и предлагает его ученику.
struct ProposeSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let studentId: UserID
    /// Заявка, на которую тренер отвечает своим временем (кнопка «Предложить другое время»).
    var replacing: BookingID? = nil
    @State private var day: Date?
    @State private var slotId: SlotID?
    @State private var comment = ""
    @State private var errorText: String?

    private var backend: DemoBackend { container.backend }
    private var coachId: UserID { container.currentUserId }

    /// Ближайшие 14 дней, в которые у тренера есть свободное время.
    private var days: [Date] {
        backend.availableDays(of: coachId).filter { $0 <= Date().addingTimeInterval(14 * 86_400) }.sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("\(replacing == nil ? "Предложить время" : "Другое время для") \(backend.name(studentId))").font(.headline)
                    if let replacing, let booking = backend.booking(replacing) {
                        Text("Вместо \(Fmt.shortDay(booking.startsAt)), \(Fmt.time(booking.startsAt)) — текущая заявка закроется")
                            .font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s) {
                            ForEach(days, id: \.self) { item in
                                let selected = item == day
                                Button {
                                    day = item
                                    slotId = nil
                                } label: {
                                    VStack {
                                        Text(item.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.locale))).font(.caption)
                                        Text(item.formatted(.dateTime.day())).font(.title3.bold())
                                    }
                                    .frame(width: 52, height: 60)
                                    .foregroundStyle(selected ? palette.onAccent : palette.textPrimary)
                                    .background {
                                        if selected {
                                            RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(palette.accent)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .glassCard(cornerRadius: Radius.m)
                            }
                        }
                    }
                    if let day {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 3), spacing: Space.s) {
                            ForEach(backend.freeSlots(of: coachId, on: day)) { slot in
                                let selected = slot.id == slotId
                                Button { slotId = slot.id } label: {
                                    VStack(spacing: 0) {
                                        Text(Fmt.time(slot.startsAt)).font(.callout.weight(.semibold).monospacedDigit())
                                        Text(backend.venue(clubId: slot.clubId)?.name ?? "").font(.caption2).lineLimit(1)
                                    }
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .foregroundStyle(selected ? palette.onAccent : palette.textPrimary)
                                        .background {
                                            if selected {
                                                RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(palette.accent)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .glassCard(cornerRadius: Radius.m)
                            }
                        }
                    } else {
                        Text("Выберите день").foregroundStyle(palette.textSecondary)
                    }
                    TextField("Комментарий: например, отработаем выход", text: $comment, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(Space.m)
                        .glassCard(cornerRadius: Radius.m)
                }
                .padding(Space.l)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Предложить ученику") { propose() }
                    .buttonStyle(.cueGlassProminent)
                    .disabled(slotId == nil)
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.s)
            }
            .background(ThemedBackground())
            .navigationTitle("Предложить время")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .errorAlert($errorText)
        }
    }

    private func propose() {
        guard let slotId else { return }
        do {
            let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if let replacing {
                try backend.counterPropose(bookingId: replacing, slotId: slotId, comment: text.isEmpty ? nil : text)
            } else {
                try backend.proposeSlot(coachId: coachId, studentId: studentId, slotId: slotId,
                                        comment: text.isEmpty ? nil : text)
            }
            dismiss()
        } catch {
            errorText = DemoBackend.message(for: error)
        }
    }
}

struct PersonRef: Identifiable, Hashable {
    let id: UserID
}

/// Профиль собеседника: тренер (для ученика), ученик (для тренера) или другой игрок клуба (для ученика).
struct PersonProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let personId: UserID

    private var backend: DemoBackend { container.backend }

    var body: some View {
        NavigationStack {
            Group {
                if let coach = backend.coach(personId) {
                    coachProfile(coach)
                } else if container.role == .trainer {
                    StudentDetailView(container: container, studentId: personId)
                } else {
                    playerProfile
                }
            }
            .background(ThemedBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
    }

    private func coachProfile(_ coach: DemoCoach) -> some View {
        ScrollView {
            VStack(spacing: Space.l) {
                Avatar(initials: coach.person.initials, size: 88, userId: coach.id)
                Text(coach.name).font(.title2.weight(.semibold)).fontDesign(palette.headingDesign)
                Text(coach.rank).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(backend.venues(of: coach.id).filter {
                        container.role == .trainer || backend.canBook(clubId: $0.clubId, student: container.currentUserId)
                    }) { venue in
                        Label("\(venue.name), \(venue.address)", systemImage: "mappin.and.ellipse")
                    }
                    Label(coach.scheduleTitle, systemImage: "clock")
                    if !coach.about.isEmpty {
                        Label(coach.about, systemImage: "person.text.rectangle")
                    }
                    // Телефон тренера виден ученику с записью к нему (BR-002.2).
                    if backend.bookings(ofStudent: container.currentUserId).contains(where: { $0.trainerId == coach.id }),
                       let url = URL(string: "tel:\(coach.person.phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) { Label(coach.person.phone, systemImage: "phone") }
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
                .glassCard()
                Button("Записаться к тренеру") {
                    dismiss()
                    container.openBooking(with: coach.id)
                }
                .buttonStyle(.cueGlassProminent)
                Button("Написать") {
                    dismiss()
                    container.openChat(with: coach.id)
                }
                .buttonStyle(.bordered)
            }
            .padding(Space.l)
        }
        .navigationTitle("Тренер")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Профиль другого ученика: публичная витрина + прогресс по его настройкам приватности. Телефона нет (BR-030.2).
    private var playerProfile: some View {
        let person = backend.person(personId)
        let progress = backend.progress(for: personId)
        let rating = backend.publicRating(of: personId)
        return ScrollView {
            VStack(spacing: Space.l) {
                Avatar(initials: person?.initials ?? "?", size: 88, userId: personId)
                Text(person?.name ?? "Игрок").font(.title2.weight(.semibold)).fontDesign(palette.headingDesign)
                Text(progress.current.level?.title ?? "Новичок").foregroundStyle(palette.textSecondary)

                if let rating {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            Text("Прогресс").font(.headline)
                            Spacer()
                            Text("\(rating)").font(.title2.bold().monospacedDigit()).foregroundStyle(palette.accent)
                        }
                        ForEach(MetricKey.allCases) { key in
                            let value = progress.current[key] ?? 0
                            VStack(alignment: .leading, spacing: Space.xs) {
                                HStack {
                                    Text(key.title)
                                    Spacer()
                                    Text("\(value)").monospacedDigit()
                                }
                                .font(.callout)
                                ProgressView(value: Double(value), total: 100).tint(palette.accent)
                            }
                        }
                    }
                    .padding(Space.l)
                    .glassCard()
                } else {
                    Label("Игрок скрыл прогресс от других учеников", systemImage: "lock.fill")
                        .foregroundStyle(palette.textSecondary)
                        .padding(Space.l)
                        .frame(maxWidth: .infinity)
                        .glassCard()
                }

                if backend.phonesShared(container.currentUserId, personId), let phone = person?.phone,
                   let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) { Label(phone, systemImage: "phone.fill") }
                } else {
                    Label("Телефон откроется, если вы обменяетесь номерами в чате", systemImage: "phone.down")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }

                Button("Написать") {
                    dismiss()
                    container.openChat(with: personId)
                }
                .buttonStyle(.cueGlassProminent)
            }
            .padding(Space.l)
        }
        .navigationTitle("Игрок")
        .navigationBarTitleDisplayMode(.inline)
    }
}
