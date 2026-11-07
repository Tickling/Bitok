// AchievementKit/Sources/AchievementUI/AchievementsScreen.swift
// «Достижения» (сегмент вкладки «Прогресс»): медали — включая медаль участника за каждый турнир,
// карточки медалей с деталями турнира, статистика турниров, достижения в процессе, приватность.
import SwiftUI
import CoreDomain
import DesignSystem
import AchievementDomain

public struct AchievementsScreen: View {
    @Environment(\.palette) private var palette
    let stats: TournamentStats
    let medalCards: [MedalCard]
    let inProgress: [AchievementProgress]
    @Binding var showToStudents: Bool

    public init(stats: TournamentStats, medalCards: [MedalCard], inProgress: [AchievementProgress],
                showToStudents: Binding<Bool>) {
        self.stats = stats
        self.medalCards = medalCards
        self.inProgress = inProgress
        self._showToStudents = showToStudents
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    ForEach(Medal.allCases, id: \.self) { medal in
                        MedalView(medal: medal, caption: "\(stats.medals[medal] ?? 0)")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(Space.m)
                .glassCard()

                ForEach(medalCards) { card in
                    medalCard(card, isFirst: card.id == medalCards.last?.id)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Space.s) {
                    stat("\(stats.tournamentsPlayed)", "турниров")
                    stat("\(stats.ballsPotted)", "шаров")
                    stat(stats.winRate.formatted(.percent.precision(.fractionLength(0))), "побед")
                }

                if !inProgress.isEmpty {
                    Text("В процессе").font(.headline)
                    ForEach(inProgress) { item in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("\(item.definition.title) · \(item.current)/\(item.definition.target)").font(.callout)
                            ProgressView(value: item.fraction).tint(palette.accent)
                        }
                        .padding(Space.m)
                        .glassCard()
                    }
                }

                Toggle("Показывать достижения другим ученикам", isOn: $showToStudents)
                    .padding(Space.l)
                    .glassCard()
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
    }

    private func medalCard(_ card: MedalCard, isFirst: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            MedalView(medal: card.medal, caption: card.medal == .participant ? "участник" : "\(card.place) место")
            VStack(alignment: .leading, spacing: Space.xs) {
                if isFirst {
                    Text("Первая медаль")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 2)
                        .background(palette.accent, in: Capsule())
                        .foregroundStyle(palette.onAccent)
                }
                Text(card.tournamentTitle).font(.headline)
                Text("\(card.date.formatted(date: .long, time: .omitted)) · \(card.clubName)")
                    .font(.caption).foregroundStyle(palette.textSecondary)
                Text("Матчи: \(card.matchesPlayed) · победы: \(card.matchesWon) · шары: \(card.ballsPotted)")
                    .font(.caption)
                if !card.defeatedOpponents.isEmpty {
                    Text("Обыграл: \(card.defeatedOpponents.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(caption).font(.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m)
        .glassCard(cornerRadius: Radius.m)
    }
}
