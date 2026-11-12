// App/Sources/RootTabView.swift — ролезависимый Tab Bar (ANALYTICS.md, раздел 8.4.4)
import SwiftUI
import CoreDomain
import DesignSystem

struct RootTabView: View {
    @Bindable var container: AppContainer

    var body: some View {
        TabView(selection: $container.selectedTab) {
            CalendarRootView(container: container)
                .tabItem { Label("Календарь", systemImage: "calendar") }
                .tag(AppTab.calendar)

            // У ученика «Прогресс» теперь в профиле (отдельный блок); у тренера — вкладка «Ученики».
            if container.role == .trainer {
                StudentsRootView(container: container)
                    .tabItem { Label("Ученики", systemImage: "person.2") }
                    .tag(AppTab.people)
            }

            ChatRootView(container: container)
                .tabItem { Label("Чат", systemImage: "bubble.left.and.bubble.right") }
                .badge(container.backend.pendingRequests(of: container.currentUserId).count
                       + container.backend.totalUnread(for: container.currentUserId))
                .tag(AppTab.chat)

            ContentRootView(container: container)
                .tabItem { Label("Контент", systemImage: "newspaper") }
                .tag(AppTab.content)

            ProfileRootView(container: container)
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .onAppear { container.backend.checkBirthdays(for: container.currentUserId) }
        // Неоткрытый подарок — сразу красивая распаковка.
        .fullScreenCover(item: Binding(
            get: { container.backend.unopenedGift(for: container.currentUserId) },
            set: { _ in }
        )) { gift in
            GiftDetailView(container: container, giftId: gift.id, animated: true)
        }
    }
}
