// App/Sources/Chat.swift — чаты, «Игроки клуба», уведомления и диалог с карточками заявок.
import SwiftUI
import CoreDomain
import DesignSystem
import BookingDomain
import BookingUI
import ChatDomain

struct ChatRootView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case chats = "Чаты", players = "Игроки", notifications = "Уведомления"
        var id: Self { self }
    }

    @Environment(\.palette) private var palette
    @Bindable var container: AppContainer
    @State private var segment: Segment = .chats

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
        }
    }

    private var chatsList: some View {
        ForEach(backend.chatPartners(of: me)) { person in
            NavigationLink(value: person.id) {
                HStack(spacing: Space.m) {
                    Avatar(initials: person.initials, size: 44)
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
        ForEach(DemoContent.players) { player in
            HStack(spacing: Space.m) {
                Avatar(initials: String(player.displayName.prefix(1)), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.displayName).font(.headline)
                    Text([player.levelTitle, player.specialTitle].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if let rating = player.overallRating {
                    Text("\(rating)").font(.title3.bold().monospacedDigit()).foregroundStyle(palette.accent)
                } else {
                    Image(systemName: "lock.fill").foregroundStyle(palette.textSecondary)
                        .accessibilityLabel("Игрок скрыл прогресс")
                }
            }
            .padding(Space.m)
            .glassCard()
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
                    Text(event.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
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
        .sheet(item: $openedBooking) { ref in
            BookingDetailView(bookingId: ref.id, container: container)
        }
        .errorAlert($errorText)
    }

    @ViewBuilder
    private func messageView(_ message: DemoMessage) -> some View {
        let mine = message.from == me
        if let bookingId = message.bookingId, let booking = backend.booking(bookingId) {
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
            Label(backend.coach(booking.trainerId)?.clubName ?? "", systemImage: "mappin.and.ellipse").font(.caption)
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
                } else {
                    HStack(spacing: Space.s) {
                        ProgressView()
                        Text("Ожидает подтверждения тренера").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Button("Подробнее") { openedBooking = BookingRef(id: booking.id) }.font(.caption)
            Text(Fmt.time(message.date)).font(.caption2).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.m)
        .frame(maxWidth: 300, alignment: .leading)
        .glassCard()
    }

    private var composer: some View {
        HStack(spacing: Space.s) {
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
