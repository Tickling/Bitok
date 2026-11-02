// ShopKit/Sources/ShopUI/ShopComingSoonView.swift — ЗАДЕЛ
import SwiftUI
import DesignSystem

public struct ShopComingSoonView: View {
    @Environment(\.palette) private var palette
    public init() {}
    public var body: some View {
        ContentUnavailableView {
            Label("Магазин скоро откроется", systemImage: "bag")
        } description: {
            Text("Кии, наклейки, мел и перчатки с рекомендациями вашего тренера и самовывозом из клуба.")
        }
        .foregroundStyle(palette.textPrimary)
        .background(ThemedBackground())
    }
}
