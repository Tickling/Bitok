// App/Sources/RootTabView.swift — ролезависимый Tab Bar (ANALYTICS.md, раздел 8.4.4)
import SwiftUI
import CoreDomain
import DesignSystem

struct RootTabView: View {
    @Bindable var container: AppContainer

    var body: some View {
        TabView {
            CalendarRootView(container: container)
                .tabItem { Label("Календарь", systemImage: "calendar") }

            if container.role == .trainer {
                StudentsRootView()
                    .tabItem { Label("Ученики", systemImage: "person.2") }
            } else {
                ProgressRootView(container: container)
                    .tabItem { Label("Прогресс", systemImage: "chart.xyaxis.line") }
            }

            ChatRootView(role: container.role)
                .tabItem { Label("Чат", systemImage: "bubble.left.and.bubble.right") }

            ContentRootView(showsShop: container.flags.shopEnabled)
                .tabItem { Label("Контент", systemImage: "newspaper") }

            ProfileRootView(container: container)
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
    }
}
