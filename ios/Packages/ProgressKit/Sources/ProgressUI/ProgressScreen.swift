// ProgressKit/Sources/ProgressUI/ProgressScreen.swift
// Экран «Прогресс» (FR-012, FR-013): уровень, радар 5 метрик (сейчас / месяц назад),
// переключатель «Радар / Шкалы», история (Swift Charts), приватность.
import SwiftUI
import Charts
import CoreDomain
import DesignSystem
import ProgressDomain

@MainActor
@Observable
public final class ProgressViewModel {
    public private(set) var progress: StudentProgress?
    public private(set) var monthAgo: PlayerMetrics?
    public private(set) var history: [ProgressSnapshot] = []
    public var privacy = PrivacySettings()
    public private(set) var errorMessage: String?

    private let studentId: UserID
    private let repository: ProgressRepository
    private let dates: DateProvider

    public init(studentId: UserID, repository: ProgressRepository, dates: DateProvider = SystemDateProvider()) {
        self.studentId = studentId
        self.repository = repository
        self.dates = dates
    }

    public func load() async {
        do {
            let now = dates.now()
            async let progress = repository.progress(studentId: studentId)
            async let history = repository.history(studentId: studentId, from: now.addingTimeInterval(-90 * 86_400), to: now)
            async let privacy = repository.privacy(studentId: studentId)
            self.progress = try await progress
            self.history = try await history
            self.privacy = try await privacy
            self.monthAgo = self.history.last { $0.date <= now.addingTimeInterval(-30 * 86_400) }?.metrics
        } catch {
            errorMessage = "Не удалось загрузить прогресс. Показаны сохранённые данные."
        }
    }

    /// Оптимистичное обновление переключателя с откатом при ошибке.
    public func setShowProgressToStudents(_ value: Bool) async {
        let previous = privacy
        privacy.showProgressToStudents = value
        do {
            privacy = try await repository.updatePrivacy(studentId: studentId, privacy)
        } catch {
            privacy = previous
            errorMessage = "Не удалось сохранить настройку"
        }
    }

    func normalized(_ metrics: PlayerMetrics?) -> [Double] {
        MetricKey.allCases.map { Double(metrics?[$0] ?? 0) / 100 }
    }
}

public struct ProgressScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case radar = "Радар", bars = "Шкалы"
        var id: Self { self }
    }

    @Environment(\.palette) private var palette
    @State private var viewModel: ProgressViewModel
    @State private var mode: Mode = .radar
    @State private var selectedMetric: MetricKey = .aiming

    public init(viewModel: ProgressViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if let progress = viewModel.progress, let rating = progress.overallRating {
                    levelCard(rating: rating, level: progress.current.level)
                    Picker("Вид", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .radar:
                        RadarChart(
                            axes: MetricKey.allCases.map(\.title),
                            series: [
                                RadarSeries(id: "Месяц назад", values: viewModel.normalized(viewModel.monthAgo),
                                            color: palette.accentSecondary, isDashed: true),
                                RadarSeries(id: "Сейчас", values: viewModel.normalized(progress.current), color: palette.accent),
                            ]
                        )
                        .glassCard()
                    case .bars:
                        bars(progress.current)
                    }
                    historyChart
                    privacyToggle
                } else {
                    ContentUnavailableView("Пока нет оценок", systemImage: "chart.xyaxis.line",
                                           description: Text("Запишитесь на тренировку — после неё тренер оценит ваши навыки."))
                }
            }
            .padding(Space.l)
        }
        .background(ThemedBackground())
        .navigationTitle("Прогресс")
        .task { await viewModel.load() }
    }

    private func levelCard(rating: Int, level: PlayerLevel?) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Уровень").font(.caption).foregroundStyle(palette.textSecondary)
                Text(level?.title ?? "—").font(.title3.weight(.semibold)).fontDesign(palette.headingDesign)
            }
            Spacer()
            Text("\(rating)").font(.system(size: 40, weight: .bold).monospacedDigit()).foregroundStyle(palette.accent)
        }
        .padding(Space.l)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private func bars(_ metrics: PlayerMetrics) -> some View {
        VStack(spacing: Space.m) {
            ForEach(MetricKey.allCases) { key in
                let value = metrics[key] ?? 0
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Label(key.title, systemImage: key.symbolName)
                        Spacer()
                        Text("\(value)").monospacedDigit().bold()
                    }
                    .font(.callout)
                    ProgressView(value: Double(value), total: 100).tint(palette.accent)
                }
            }
        }
        .padding(Space.l)
        .glassCard()
    }

    private var historyChart: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Picker("Метрика", selection: $selectedMetric) {
                ForEach(MetricKey.allCases) { Text($0.title).tag($0) }
            }
            Chart(viewModel.history) { point in
                if let value = point.metrics[selectedMetric] {
                    LineMark(x: .value("Дата", point.date), y: .value("Значение", value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(palette.accent)
                    PointMark(x: .value("Дата", point.date), y: .value("Значение", value))
                        .foregroundStyle(palette.accent)
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 180)
        }
        .padding(Space.l)
        .glassCard()
    }

    private var privacyToggle: some View {
        Toggle(isOn: Binding(
            get: { viewModel.privacy.showProgressToStudents },
            set: { newValue in Task { await viewModel.setShowProgressToStudents(newValue) } }
        )) {
            VStack(alignment: .leading) {
                Text("Показывать прогресс другим ученикам")
                Text("Ваш тренер видит прогресс всегда").font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.l)
        .glassCard()
    }
}
