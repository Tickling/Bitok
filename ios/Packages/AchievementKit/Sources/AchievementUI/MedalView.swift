// AchievementKit/Sources/AchievementUI/MedalView.swift
import SwiftUI
import DesignSystem
import AchievementDomain

public struct MedalView: View {
    let medal: Medal
    let caption: String
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 44

    public init(medal: Medal, caption: String) {
        self.medal = medal
        self.caption = caption
    }

    public var body: some View {
        VStack(spacing: Space.xs) {
            Circle()
                .fill(RadialGradient(colors: stops, center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: size))
                .frame(width: size, height: size)
                .overlay(Image(systemName: medal == .participant ? "ribbon" : "trophy.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.black.opacity(0.55)))
            Text(caption).font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(medal.title), \(caption)")
    }

    private var stops: [Color] {
        switch medal {
        case .gold: [Color(hex: 0xFFF6C8), Color(hex: 0xF2C94C), Color(hex: 0xB8860B)]
        case .silver: [.white, Color(hex: 0xC9CED6), Color(hex: 0x8A929E)]
        case .bronze: [Color(hex: 0xFFE0C2), Color(hex: 0xD08B4F), Color(hex: 0x8A4F1F)]
        case .participant: [Color(hex: 0xE9EEF3), Color(hex: 0x8FA3B5), Color(hex: 0x4A5B6B)]
        }
    }
}
