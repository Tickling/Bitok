// App/Sources/ChatGroups.swift — групповые чаты: ученики-друзья (обменялись номерами или договорились сыграть)
// создают группу, могут добавить тренера; любой участник может покинуть группу.
import SwiftUI
import CoreDomain
import DesignSystem

struct DemoChatGroup: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var members: [UserID]
    let creatorId: UserID
    var date = Date()
}

struct DemoGroupMessage: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let groupId: UUID
    let from: UserID?          // nil — системное сообщение («Иван покинул группу»)
    var text: String
    var date = Date()
}

extension DemoBackend {
    func chatGroups(for userId: UserID) -> [DemoChatGroup] {
        chatGroupsStore.filter { $0.members.contains(userId) }
            .sorted { (lastGroupMessage($0.id)?.date ?? $0.date) > (lastGroupMessage($1.id)?.date ?? $1.date) }
    }

    func chatGroup(_ id: UUID) -> DemoChatGroup? { chatGroupsStore.first { $0.id == id } }

    func groupMessages(_ id: UUID) -> [DemoGroupMessage] {
        groupMessagesStore.filter { $0.groupId == id }.sorted { $0.date < $1.date }
    }

    func lastGroupMessage(_ id: UUID) -> DemoGroupMessage? { groupMessages(id).last }

    @discardableResult
    func createChatGroup(title: String, members: [UserID], creator: UserID) -> DemoChatGroup {
        let group = DemoChatGroup(title: title, members: [creator] + members.filter { $0 != creator }, creatorId: creator)
        chatGroupsStore.append(group)
        groupMessagesStore.append(DemoGroupMessage(groupId: group.id, from: nil, text: "\(name(creator)) создал(а) группу «\(title)»"))
        for member in group.members where member != creator {
            notify(member, "Вас добавили в группу «\(title)»", "Создатель: \(name(creator))")
        }
        save()
        return group
    }

    func sendToGroup(_ id: UUID, from: UserID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let group = chatGroup(id), group.members.contains(from) else { return }
        groupMessagesStore.append(DemoGroupMessage(groupId: id, from: from, text: trimmed))
        for member in group.members where member != from {
            notify(member, "\(group.title): \(name(from))", trimmed)
        }
        save()
    }

    func addToGroup(_ id: UUID, member: UserID, by userId: UserID) {
        guard let index = chatGroupsStore.firstIndex(where: { $0.id == id }), !chatGroupsStore[index].members.contains(member) else { return }
        chatGroupsStore[index].members.append(member)
        groupMessagesStore.append(DemoGroupMessage(groupId: id, from: nil, text: "\(name(userId)) добавил(а) \(name(member))"))
        notify(member, "Вас добавили в группу «\(chatGroupsStore[index].title)»", name(userId))
        save()
    }

    func leaveGroup(_ id: UUID, userId: UserID) {
        guard let index = chatGroupsStore.firstIndex(where: { $0.id == id }) else { return }
        chatGroupsStore[index].members.removeAll { $0 == userId }
        groupMessagesStore.append(DemoGroupMessage(groupId: id, from: nil, text: "\(name(userId)) покинул(а) группу"))
        if chatGroupsStore[index].members.isEmpty { chatGroupsStore.remove(at: index) }
        save()
    }
}

// MARK: - Экраны

struct GroupRow: View {
    @Environment(\.palette) private var palette
    let backend: DemoBackend
    let group: DemoChatGroup

    /// «Иван: текст» или «N участников».
    private var preview: String {
        guard let last = backend.lastGroupMessage(group.id) else { return "\(group.members.count) участников" }
        guard let from = last.from else { return last.text }
        let first = backend.name(from).split(separator: " ").first.map(String.init) ?? ""
        return first + ": " + last.text
    }

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "person.3.fill")
                .foregroundStyle(palette.onAccent)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [palette.accentSecondary, palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(group.title).font(.headline)
                    Spacer()
                    if let last = backend.lastGroupMessage(group.id) {
                        Text(Fmt.time(last.date)).font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Text(preview)
                    .font(.callout).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
        }
        .padding(Space.m)
        .glassCard()
    }
}

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    var onCreated: (UUID) -> Void = { _ in }
    @State private var title = ""
    @State private var selected: Set<UserID> = []

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: «Пятничная пирамида»", text: $title)
                }
                Section {
                    let friends = backend.friends(of: me)
                    if friends.isEmpty {
                        Text("Пока нет друзей. Предложите ученику сыграть или обменяться номерами в чате — после согласия его можно добавить в группу.")
                            .font(.callout).foregroundStyle(palette.textSecondary)
                    }
                    ForEach(friends) { friend in row(friend.id, subtitle: "Ученик") }
                } header: {
                    Text("Друзья")
                }
                Section("Тренер (по желанию)") {
                    ForEach(backend.coaches) { coach in row(coach.id, subtitle: coach.rank) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground())
            .navigationTitle("Новая группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        let group = backend.createChatGroup(title: title.trimmingCharacters(in: .whitespaces), members: Array(selected), creator: me)
                        dismiss()
                        onCreated(group.id)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                }
            }
        }
    }

    private func row(_ id: UserID, subtitle: String) -> some View {
        Button {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        } label: {
            HStack {
                Avatar(initials: backend.person(id)?.initials ?? "?", size: 34, userId: id)
                VStack(alignment: .leading) {
                    Text(backend.name(id)).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle").foregroundStyle(palette.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

struct GroupChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let container: AppContainer
    let groupId: UUID
    @State private var draft = ""
    @State private var showMembers = false
    @State private var confirmLeave = false

    private var backend: DemoBackend { container.backend }
    private var me: UserID { container.currentUserId }

    var body: some View {
        let group = backend.chatGroup(groupId)
        let messages = backend.groupMessages(groupId)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.s) {
                    ForEach(messages) { message in bubble(message).id(message.id) }
                }
                .padding(Space.l)
            }
            .onAppear { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            .onChange(of: messages.count) { _, _ in if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
        }
        .safeAreaInset(edge: .bottom) {
            if group?.members.contains(me) == true {
                HStack(spacing: Space.s) {
                    TextField("Сообщение в группу", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                        .glassCard(cornerRadius: 22)
                    Button {
                        backend.sendToGroup(groupId, from: me, text: draft)
                        draft = ""
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            } else {
                Text("Вы покинули группу").font(.callout).foregroundStyle(palette.textSecondary).padding()
            }
        }
        .background(ThemedBackground())
        .navigationTitle(group?.title ?? "Группа")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMembers = true } label: {
                    Label("\(group?.members.count ?? 0)", systemImage: "person.3")
                }
            }
        }
        .sheet(isPresented: $showMembers) {
            NavigationStack {
                List {
                    Section("Участники") {
                        ForEach(group?.members ?? [], id: \.self) { id in
                            HStack {
                                Avatar(initials: backend.person(id)?.initials ?? "?", size: 32, userId: id)
                                Text(id == me ? "Вы" : backend.name(id))
                                Spacer()
                                if backend.isCoach(id) { Text("тренер").font(.caption).foregroundStyle(palette.textSecondary) }
                            }
                        }
                    }
                    let candidates = (backend.friends(of: me).map(\.id) + backend.coaches.map(\.id)).filter { !(group?.members.contains($0) ?? true) }
                    if !candidates.isEmpty && group?.members.contains(me) == true {
                        Section("Добавить") {
                            ForEach(candidates, id: \.self) { id in
                                Button { backend.addToGroup(groupId, member: id, by: me) } label: {
                                    Label(backend.name(id), systemImage: "plus.circle")
                                }
                            }
                        }
                    }
                    if group?.members.contains(me) == true {
                        Section {
                            Button("Покинуть группу", role: .destructive) { confirmLeave = true }
                        }
                    }
                }
                .navigationTitle(group?.title ?? "Группа")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { showMembers = false } } }
                .confirmationDialog("Покинуть группу «\(group?.title ?? "")»?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Покинуть", role: .destructive) {
                        backend.leaveGroup(groupId, userId: me)
                        showMembers = false
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: DemoGroupMessage) -> some View {
        if let from = message.from {
            let mine = from == me
            HStack(alignment: .bottom) {
                if mine { Spacer(minLength: 48) } else { Avatar(initials: backend.person(from)?.initials ?? "?", size: 26, userId: from) }
                VStack(alignment: .leading, spacing: 2) {
                    if !mine {
                        Text(backend.name(from) + (backend.isCoach(from) ? " · тренер" : ""))
                            .font(.caption.weight(.semibold)).foregroundStyle(palette.accent)
                    }
                    Text(message.text)
                    Text(Fmt.time(message.date)).font(.caption2).opacity(0.7).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .foregroundStyle(mine ? palette.onAccent : palette.textPrimary)
                .background { if mine { RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(palette.accent) } }
                .glassCard(cornerRadius: Radius.l)
                .frame(maxWidth: 280, alignment: mine ? .trailing : .leading)
                if !mine { Spacer(minLength: 48) }
            }
        } else {
            Text(message.text).font(.caption).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.m).padding(.vertical, 4)
                .background(palette.textSecondary.opacity(0.12), in: Capsule())
                .frame(maxWidth: .infinity)
        }
    }
}
