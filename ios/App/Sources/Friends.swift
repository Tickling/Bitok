// App/Sources/Friends.swift — друзья среди учеников: запрос → согласие второй стороны → взаимная дружба.
// Согласие сыграть или обменяться номерами тоже добавляет в друзья. Друзей можно звать в групповые чаты.
import SwiftUI
import CoreDomain
import DesignSystem

enum FriendStatus { case none, outgoing, incoming, friends }

extension DemoBackend {
    func areFriends(_ a: UserID, _ b: UserID) -> Bool { friendships[a]?.contains(b) == true }

    func friends(of userId: UserID) -> [DemoPerson] {
        (friendships[userId] ?? []).compactMap { person($0) }.sorted { $0.name < $1.name }
    }

    func addFriends(_ a: UserID, _ b: UserID) {
        guard a != b, !isCoach(a), !isCoach(b) else { return }
        friendships[a, default: []].insert(b)
        friendships[b, default: []].insert(a)
        save()
    }

    /// Удалить из друзей — у обоих, без уведомления.
    func removeFriend(_ userId: UserID, _ other: UserID) {
        friendships[userId]?.remove(other)
        friendships[other]?.remove(userId)
        save()
    }

    func friendStatus(_ me: UserID, _ other: UserID) -> FriendStatus {
        if areFriends(me, other) { return .friends }
        let pending = conversation(between: me, and: other).last { $0.peerRequest?.kind == .friendRequest && $0.peerRequest?.status == .sent }
        guard let pending else { return .none }
        return pending.from == me ? .outgoing : .incoming
    }

    /// Входящие запросы в друзья (сообщения с карточкой запроса).
    func incomingFriendRequests(_ userId: UserID) -> [DemoMessage] {
        messages.filter { $0.to == userId && $0.peerRequest?.kind == .friendRequest && $0.peerRequest?.status == .sent }
            .sorted { $0.date > $1.date }
    }

    func pendingFriendRequest(from: UserID, to: UserID) -> DemoMessage? {
        messages.last { $0.from == from && $0.to == to && $0.peerRequest?.kind == .friendRequest && $0.peerRequest?.status == .sent }
    }

    func cancelFriendRequest(from: UserID, to: UserID) {
        guard let message = pendingFriendRequest(from: from, to: to) else { return }
        messages.removeAll { $0.id == message.id }
        save()
    }

    func seedFriends() {
        addFriends(DemoBackend.ivanId, DemoBackend.natashaId)
        // Мария хочет дружить с Иваном — входящий запрос для демо.
        messages.append(DemoMessage(id: UUID(), from: students[1].id, to: DemoBackend.ivanId, text: "Хочу добавить вас в друзья 🤝",
                                    date: Date().addingTimeInterval(-1800), peerRequest: DemoPeerRequest(kind: .friendRequest, status: .sent)))
    }
}

/// Кнопка дружбы в профиле ученика: меняется по состоянию.
struct FriendButton: View {
    let container: AppContainer
    let otherId: UserID
    @State private var confirmRemove = false

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        switch backend.friendStatus(me, otherId) {
        case .none:
            Button {
                try? backend.sendPeerRequest(.friendRequest, from: me, to: otherId)
            } label: { Label("Добавить в друзья", systemImage: "person.badge.plus") }
                .buttonStyle(.cueGlassProminent)
        case .outgoing:
            Button { backend.cancelFriendRequest(from: me, to: otherId) } label: {
                Label("Запрос отправлен · отменить", systemImage: "clock")
            }
            .buttonStyle(.cueSecondary)
        case .incoming:
            HStack(spacing: Space.s) {
                Button("Принять в друзья") {
                    if let request = backend.pendingFriendRequest(from: otherId, to: me) {
                        try? backend.answerPeerRequest(messageId: request.id, by: me, accept: true)
                    }
                }
                .buttonStyle(.cueGlassProminent)
                Button("Отклонить", role: .destructive) {
                    if let request = backend.pendingFriendRequest(from: otherId, to: me) {
                        try? backend.answerPeerRequest(messageId: request.id, by: me, accept: false)
                    }
                }
                .buttonStyle(.cueSecondary)
            }
        case .friends:
            Button { confirmRemove = true } label: { Label("В друзьях ✓", systemImage: "person.2.fill") }
                .buttonStyle(.cueSecondary)
                .confirmationDialog("Удалить \(backend.name(otherId)) из друзей?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Удалить из друзей", role: .destructive) { backend.removeFriend(me, otherId) }
                }
        }
    }
}

/// Друзья и запросы — из профиля ученика.
struct FriendsView: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var profile: PersonRef?

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                FriendsSections(container: container) { profile = PersonRef(id: $0) }
                Text("Добавить друга можно в «Чат» → «Ученики» или в профиле ученика. Друзей можно звать в групповые чаты.")
                    .font(.caption).foregroundStyle(palette.textSecondary)
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("Друзья")
        .sheet(item: $profile) { ref in PersonProfileSheet(container: container, personId: ref.id) }
    }
}

/// Блоки «Запросы в друзья» и «Друзья» (используются в профиле и в «Чат» → «Ученики»).
struct FriendsSections: View {
    @Environment(\.palette) private var palette
    let container: AppContainer
    let onOpen: (UserID) -> Void

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        let requests = backend.incomingFriendRequests(me)
        if !requests.isEmpty {
            Label("Запросы в друзья · \(requests.count)", systemImage: "person.badge.plus").font(.headline)
                .foregroundStyle(palette.accent)
            ForEach(requests) { request in
                VStack(alignment: .leading, spacing: Space.s) {
                    Button { onOpen(request.from) } label: {
                        HStack(spacing: Space.m) {
                            Avatar(initials: backend.person(request.from)?.initials ?? "?", size: 40, userId: request.from)
                            VStack(alignment: .leading) {
                                Text(backend.name(request.from)).font(.headline)
                                Text("хочет добавить вас в друзья").font(.caption).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: Space.s) {
                        Button("Принять") { try? backend.answerPeerRequest(messageId: request.id, by: me, accept: true) }
                            .buttonStyle(.cueGlassProminent)
                        Button("Отклонить", role: .destructive) { try? backend.answerPeerRequest(messageId: request.id, by: me, accept: false) }
                            .buttonStyle(.cueSecondary)
                    }
                }
                .padding(Space.m)
                .glassCard()
            }
        }
        let friends = backend.friends(of: me)
        Label("Друзья · \(friends.count)", systemImage: "person.2.fill").font(.headline)
        if friends.isEmpty {
            Text("Пока нет друзей").font(.callout).foregroundStyle(palette.textSecondary)
        }
        ForEach(friends) { friend in
            Button { onOpen(friend.id) } label: {
                HStack(spacing: Space.m) {
                    Avatar(initials: friend.initials, size: 40, userId: friend.id)
                    VStack(alignment: .leading) {
                        Text(friend.name).font(.headline)
                        let coaches = backend.coachesOf(friend.id).map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
                        Text(coaches.isEmpty ? "Пока без тренера" : "Тренер: " + coaches.joined(separator: ", "))
                            .font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Button { container.openChat(with: friend.id) } label: { Image(systemName: "bubble.left.fill") }
                        .buttonStyle(.borderless)
                }
                .padding(Space.m)
                .glassCard()
            }
            .buttonStyle(.plain)
        }
    }
}
