// DesignSystem/Sources/DesignSystem/Glass.swift
import SwiftUI

public enum Radius {
    public static let s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 18, xl: CGFloat = 26
}

public enum Space {
    public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
}

/// Стеклянная карточка: Liquid Glass на iOS 26+, материал на iOS 17–25, непрозрачная — при Reduce Transparency.
public struct GlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.palette) private var palette
    var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) { self.cornerRadius = cornerRadius }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(palette.surfaceOpaque, in: shape)
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26, macOS 26, *) {
                // Liquid Glass (iOS 26 SDK, Xcode 26+)
                content.glassEffect(.regular.tint(palette.glassTint), in: shape)
            } else {
                materialFallback(content, shape: shape)
            }
            #else
            materialFallback(content, shape: shape)
            #endif
        }
    }
}

extension GlassCard {
    /// iOS 17–25: материал + тонкая обводка.
    func materialFallback(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(palette.glassStroke, lineWidth: 1))
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = Radius.l) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

/// Главная кнопка действия (CTA).
public struct CueGlassProminentButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(palette.accent, in: Capsule())
            .shadow(color: palette.accent.opacity(isEnabled ? 0.35 : 0), radius: 12, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == CueGlassProminentButtonStyle {
    static var cueGlassProminent: CueGlassProminentButtonStyle { CueGlassProminentButtonStyle() }
}

/// Пилюля статуса: цвет + иконка + текст (цвет не единственный носитель смысла).
public struct StatusPill: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    let color: KeyPath<Palette, Color>

    public init(title: String, systemImage: String, color: KeyPath<Palette, Color>) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    public var body: some View {
        let tint = palette[keyPath: color]
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35)))
    }
}
