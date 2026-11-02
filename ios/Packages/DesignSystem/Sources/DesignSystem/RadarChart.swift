// DesignSystem/Sources/DesignSystem/RadarChart.swift — радар без пропусков кадров
import SwiftUI
import Accessibility

public struct RadarSeries: Identifiable, Sendable {
    public let id: String
    public let values: [Double]      // 0…1, порядок = порядок осей
    public let color: Color
    public let isDashed: Bool

    public init(id: String, values: [Double], color: Color, isDashed: Bool = false) {
        self.id = id
        self.values = values
        self.color = color
        self.isDashed = isDashed
    }
}

/// Контур серии — Shape с animatableData: SwiftUI интерполирует только одно число, путь строится заново.
struct RadarShape: Shape {
    var values: [Double]
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for (index, value) in values.enumerated() {
            let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(values.count)
            let point = CGPoint(x: center.x + cos(angle) * radius * value * progress,
                                y: center.y + sin(angle) * radius * value * progress)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

public struct RadarChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette
    @State private var progress: Double = 0
    let axes: [String]
    let series: [RadarSeries]

    public init(axes: [String], series: [RadarSeries]) {
        self.axes = axes
        self.series = series
    }

    public var body: some View {
        ZStack {
            // Сетка и подписи статичны — рисуются одним Canvas без анимации.
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                for level in [1.0 / 3, 2.0 / 3, 1.0] {
                    var ring = Path()
                    for i in axes.indices {
                        let angle = -Double.pi / 2 + Double(i) * 2 * .pi / Double(axes.count)
                        let point = CGPoint(x: center.x + cos(angle) * radius * level, y: center.y + sin(angle) * radius * level)
                        i == 0 ? ring.move(to: point) : ring.addLine(to: point)
                    }
                    ring.closeSubpath()
                    context.stroke(ring, with: .color(palette.textSecondary.opacity(0.25)), lineWidth: 1)
                }
            }
            ForEach(series) { item in
                RadarShape(values: item.values, progress: progress)
                    .fill(item.isDashed ? Color.clear : item.color.opacity(0.22))
                RadarShape(values: item.values, progress: progress)
                    .stroke(item.color, style: StrokeStyle(lineWidth: 2, dash: item.isDashed ? [4, 4] : []))
            }
        }
        .padding(Space.xl)
        .overlay { axisLabels }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            if reduceMotion { progress = 1 } else { withAnimation(.spring(duration: 0.6)) { progress = 1 } }
        }
        .accessibilityElement()
        .accessibilityChartDescriptor(self)
    }

    private var axisLabels: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) / 2 - Space.s
            ForEach(Array(axes.enumerated()), id: \.offset) { index, title in
                let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(axes.count)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .position(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            }
        }
    }
}

extension RadarChart: AXChartDescriptorRepresentable {
    public func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Метрика", categoryOrder: axes)
        let yAxis = AXNumericDataAxisDescriptor(title: "Значение", range: 0...100, gridlinePositions: [0, 50, 100]) {
            "\(Int($0)) из 100"
        }
        let descriptors = series.map { item in
            AXDataSeriesDescriptor(name: item.id, isContinuous: false,
                                   dataPoints: zip(axes, item.values).map { AXDataPoint(x: $0, y: $1 * 100) })
        }
        return AXChartDescriptor(title: "Метрики игрока", summary: nil, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: descriptors)
    }
}
