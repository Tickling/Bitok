// AchievementKit/Sources/AchievementUI/ProfileFrameView.swift
import SwiftUI
import DesignSystem
import AchievementDomain

public enum FrameStyle: String, CaseIterable, Sendable {
    case gold, silver, bronze, steel, graphite, aura, legend

    var colors: [Color] {
        switch self {
        case .gold, .legend: [Color(hex: 0xFFF6C8), Color(hex: 0xF2C94C), Color(hex: 0xB8860B), Color(hex: 0xF2C94C), Color(hex: 0xFFF6C8)]
        case .silver: [.white, Color(hex: 0xC9CED6), Color(hex: 0x8A929E), Color(hex: 0xC9CED6), .white]
        case .bronze: [Color(hex: 0xFFE0C2), Color(hex: 0xD08B4F), Color(hex: 0x8A4F1F), Color(hex: 0xD08B4F), Color(hex: 0xFFE0C2)]
        case .steel: [Color(hex: 0xE9EEF3), Color(hex: 0x8FA3B5), Color(hex: 0xE9EEF3)]
        case .graphite: [Color(hex: 0x2B2F36), Color(hex: 0x4A505B), Color(hex: 0xC9A25C), Color(hex: 0x2B2F36)]
        case .aura: [] // берётся из акцентов оформления
        }
    }

    var rotates: Bool { [.gold, .silver, .legend].contains(self) }
    var hasParticles: Bool { self == .legend }
}

public struct ProfileFrameView<Avatar: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette
    @State private var isVisible = false
    private let style: FrameStyle?
    private let avatar: Avatar

    public init(style: FrameStyle?, @ViewBuilder avatar: () -> Avatar) {
        self.style = style
        self.avatar = avatar()
    }

    public var body: some View {
        let animate = isVisible && !reduceMotion && (style?.rotates ?? false)
        TimelineView(.animation(paused: !animate)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(animate ? seconds.truncatingRemainder(dividingBy: 6) / 6 * 360 : 0)
            avatar
                .clipShape(Circle())
                .padding(5)
                .background {
                    if let style {
                        Circle().fill(AngularGradient(colors: colors(for: style), center: .center, angle: angle))
                    }
                }
                .overlay {
                    if style?.hasParticles == true, animate {
                        SparkleLayer(time: seconds).allowsHitTesting(false)
                    }
                }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }   // не тратим кадры, когда профиль не на экране
        .accessibilityElement(children: .combine)
        .accessibilityLabel(style.map { "Рамка: \($0.rawValue)" } ?? "Без рамки")
    }

    private func colors(for style: FrameStyle) -> [Color] {
        style == .aura ? [palette.accent, palette.accentSecondary, palette.accent] : style.colors
    }
}

/// Искры для рамки «Легенда»: ≤ 24 частиц, детерминированные траектории (без аллокаций на кадр).
struct SparkleLayer: View {
    let time: TimeInterval
    private static let count = 24

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for i in 0..<Self.count {
                let seed = Double(i) / Double(Self.count)
                let phase = (time * 0.35 + seed).truncatingRemainder(dividingBy: 1)
                let angle = seed * 2 * .pi + time * 0.6
                let distance = radius * (0.95 + phase * 0.25)
                let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                let side = 3 * (1 - phase)
                context.opacity = 1 - phase
                context.fill(Path(ellipseIn: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)),
                             with: .color(Color(hex: 0xFFF6C8)))
            }
        }
    }
}
