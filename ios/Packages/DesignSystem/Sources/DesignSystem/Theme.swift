// DesignSystem/Sources/DesignSystem/Theme.swift
import SwiftUI
import Observation

public enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto, ivory, midnight
    public var id: Self { self }
    public var title: String {
        switch self {
        case .auto: "Авто"
        case .ivory: "Ivory & Oxblood"
        case .midnight: "Midnight Chalk"
        }
    }
}

public struct Palette: Sendable, Equatable {
    public let colorScheme: ColorScheme
    public let backgroundStart: Color, backgroundEnd: Color
    public let glowPrimary: Color, glowSecondary: Color
    public let glassTint: Color, glassStroke: Color, surfaceOpaque: Color
    public let textPrimary: Color, textSecondary: Color
    public let accent: Color, onAccent: Color, accentSecondary: Color
    public let statusPending: Color, statusPayment: Color, statusConfirmed: Color
    public let statusCompleted: Color, statusCancelled: Color
    public let headingDesign: Font.Design
}

public extension Palette {
    static let ivory = Palette(
        colorScheme: .light,
        backgroundStart: Color(hex: 0xFBF6EE), backgroundEnd: Color(hex: 0xF3E9DA),
        glowPrimary: Color(hex: 0x7A1C2B, opacity: 0.10), glowSecondary: Color(hex: 0xB08946, opacity: 0.16),
        glassTint: .white.opacity(0.58), glassStroke: Color(hex: 0x7A1C2B, opacity: 0.12), surfaceOpaque: Color(hex: 0xFFFDF9),
        textPrimary: Color(hex: 0x2A1A14), textSecondary: Color(hex: 0x2A1A14, opacity: 0.58),
        accent: Color(hex: 0x7A1C2B), onAccent: Color(hex: 0xFFF7EF), accentSecondary: Color(hex: 0xB08946),
        statusPending: Color(hex: 0xC98A1A), statusPayment: Color(hex: 0x6B4FA0), statusConfirmed: Color(hex: 0x2F5D8A),
        statusCompleted: Color(hex: 0x4E7D4A), statusCancelled: Color(hex: 0xB23A3A),
        headingDesign: .serif
    )

    static let midnight = Palette(
        colorScheme: .dark,
        backgroundStart: Color(hex: 0x0B1020), backgroundEnd: Color(hex: 0x111A33),
        glowPrimary: Color(hex: 0x4DA3FF, opacity: 0.26), glowSecondary: Color(hex: 0xC9A25C, opacity: 0.16),
        glassTint: .white.opacity(0.08), glassStroke: .white.opacity(0.14), surfaceOpaque: Color(hex: 0x141C33),
        textPrimary: Color(hex: 0xEEF3FF), textSecondary: Color(hex: 0xDEE7FF, opacity: 0.62),
        accent: Color(hex: 0x4DA3FF), onAccent: Color(hex: 0x06122A), accentSecondary: Color(hex: 0xC9A25C),
        statusPending: Color(hex: 0xF5B544), statusPayment: Color(hex: 0xA78BFA), statusConfirmed: Color(hex: 0x4DA3FF),
        statusCompleted: Color(hex: 0x7BD88F), statusCancelled: Color(hex: 0xFF6B6B),
        headingDesign: .default
    )
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Выбор оформления. Хранится локально и синхронизируется в профиль.
@MainActor
@Observable
public final class ThemeManager {
    private static let storageKey = "appearanceMode"
    private let defaults: UserDefaults

    public var mode: AppearanceMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.storageKey) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = AppearanceMode(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .auto
    }

    /// «Авто»: светлая системная тема → Ivory & Oxblood, тёмная → Midnight Chalk.
    public func palette(for systemScheme: ColorScheme) -> Palette {
        switch mode {
        case .auto: systemScheme == .dark ? .midnight : .ivory
        case .ivory: .ivory
        case .midnight: .midnight
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .ivory
}

public extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Корневой контейнер: прокидывает палитру и фиксирует системную схему для ручного выбора.
public struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(ThemeManager.self) private var themes
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        let palette = themes.palette(for: systemScheme)
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
            .preferredColorScheme(themes.mode == .auto ? nil : palette.colorScheme)
            .animation(.easeInOut(duration: 0.35), value: palette)
    }
}

/// Фон экрана: градиент + два статичных световых пятна.
public struct ThemedBackground: View {
    @Environment(\.palette) private var palette
    public init() {}
    public var body: some View {
        ZStack {
            LinearGradient(colors: [palette.backgroundStart, palette.backgroundEnd], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [palette.glowPrimary, .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [palette.glowSecondary, .clear], center: .bottomLeading, startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}
