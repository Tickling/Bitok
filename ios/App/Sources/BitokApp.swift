// App/Sources/BitokApp.swift — точка входа «Биток»
import SwiftUI
import CoreDomain
import DesignSystem

@main
struct BitokApp: App {
    @State private var themes = ThemeManager()
    @State private var container = AppContainer.demo()
    @AppStorage(TextSize.storageKey) private var textSize = TextSize.standard.rawValue

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                if container.account == nil {
                    DemoLoginView(container: container)
                } else {
                    RootTabView(container: container)
                }
            }
            .environment(themes)
            .dynamicTypeSize((TextSize(rawValue: textSize) ?? .standard).dynamicType)
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .onOpenURL { url in
                // Возврат из банка (universal link /pay/return) лишь будит обновление статуса —
                // подтверждение оплаты только по серверному webhook (BR-020.6).
                container.handle(url)
            }
        }
    }
}
