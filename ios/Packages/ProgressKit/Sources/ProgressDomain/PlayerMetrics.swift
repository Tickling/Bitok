// ProgressKit/Sources/ProgressDomain/PlayerMetrics.swift
import Foundation
import CoreDomain

/// 5 метрик оценки игрока, шкала 0–100 (FR-011).
public enum MetricKey: String, Codable, Sendable, CaseIterable, Identifiable {
    case stanceAndStroke, aiming, positionPlay, cueBallControl, tacticalThinking, objectBall, ownBall

    public var id: String { rawValue }

    public var title: String {
        switch self {
        // Метрики по упражнениям подготовительного уровня (ANALYTICS.md, раздел «Упражнения»).
        case .stanceAndStroke: "Стойка и мост"
        case .aiming: "Удар в середину"
        case .positionPlay: "Удар в угол"
        case .cueBallControl: "Сила и возврат битка"
        case .tacticalThinking: "Винт"
        case .objectBall: "Чужой шар"
        case .ownBall: "Свояк"
        }
    }

    public var symbolName: String {
        switch self {
        case .stanceAndStroke: "figure.stand"
        case .aiming: "scope"
        case .positionPlay: "arrow.up.left"
        case .cueBallControl: "circle.circle"
        case .tacticalThinking: "arrow.clockwise.circle"
        case .objectBall: "circle.lefthalf.filled"
        case .ownBall: "arrow.triangle.branch"
        }
    }
}

/// Уровень игрока по Overall Rating — основа автоматических титулов (FR-016).
public enum PlayerLevel: String, Codable, Sendable, CaseIterable {
    case novice, amateur, advanced, professional, master

    public init(rating: Int) {
        switch rating {
        case ..<21: self = .novice
        case 21...45: self = .amateur
        case 46...70: self = .advanced
        case 71...90: self = .professional
        default: self = .master
        }
    }

    public var title: String {
        switch self {
        case .novice: "Новичок"
        case .amateur: "Любитель"
        case .advanced: "Продвинутый"
        case .professional: "Профессионал"
        case .master: "Мастер"
        }
    }
}

/// Текущие значения метрик (0–100). Отсутствующий ключ = метрика ещё не оценивалась.
public struct PlayerMetrics: Hashable, Codable, Sendable {
    public private(set) var values: [MetricKey: Int]

    public static let range: ClosedRange<Int> = 0...100
    public static let smoothing: Double = 0.4 // α для EMA (BR-011.3)

    public init(values: [MetricKey: Int] = [:]) {
        self.values = values.mapValues { min(max($0, Self.range.lowerBound), Self.range.upperBound) }
    }

    public subscript(_ key: MetricKey) -> Int? { values[key] }

    /// Overall Rating — среднее по оценённым метрикам (все 5 метрик равновесны).
    public var overallRating: Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.values.reduce(0, +)) / Double(values.count)).rounded())
    }

    public var level: PlayerLevel? { overallRating.map(PlayerLevel.init(rating:)) }

    /// Применяет новую оценку через EMA. Неоценённые метрики не изменяются (BR-011.5).
    public func applying(_ scores: EvaluationScores) -> PlayerMetrics {
        var updated = values
        for (key, score) in scores.values {
            if let current = updated[key] {
                let ema = Self.smoothing * Double(score) + (1 - Self.smoothing) * Double(current)
                updated[key] = Int(ema.rounded())
            } else {
                updated[key] = score
            }
        }
        return PlayerMetrics(values: updated)
    }

    /// Самая слабая метрика — для рекомендаций уроков (FR-019).
    public var weakest: MetricKey? { values.min { $0.value < $1.value }?.key }

    /// Разница с прошлым снимком — для подписи «+6 за месяц» на радаре.
    public func delta(from previous: PlayerMetrics) -> [MetricKey: Int] {
        values.reduce(into: [:]) { result, entry in
            if let old = previous[entry.key] { result[entry.key] = entry.value - old }
        }
    }
}

/// Оценки одной тренировки (0–100, частичные допустимы).
public struct EvaluationScores: Hashable, Codable, Sendable {
    public let values: [MetricKey: Int]

    public init(_ values: [MetricKey: Int]) throws(DomainValidationError) {
        guard !values.isEmpty else { throw DomainValidationError.emptyEvaluation }
        for (key, value) in values where !PlayerMetrics.range.contains(value) {
            throw DomainValidationError.invalidScore(metric: key.rawValue, value: value)
        }
        self.values = values
    }
}
