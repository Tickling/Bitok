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

            Group {
                if container.role == .trainer {
                    StudentsRootView(container: container)
                        .tabItem { Label("Ученики", systemImage: "person.2") }
                } else {
                    ProgressRootView(container: container)
                        .tabItem { Label("Прогресс", systemImage: "chart.xyaxis.line") }
                }
            }
            .tag(AppTab.people)

            ChatRootView(container: container)
                .tabItem { Label("Чат", systemImage: "bubble.left.and.bubble.right") }
                .badge(container.backend.pendingRequests(of: container.currentUserId).count)
                .tag(AppTab.chat)

            ContentRootView(showsShop: container.flags.shopEnabled)
                .tabItem { Label("Контент", systemImage: "newspaper") }
                .tag(AppTab.content)

            ProfileRootView(container: container)
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
    }
}
