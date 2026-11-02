// BookingKit/Sources/BookingUI/MonthGrid.swift — сетка месяца
import SwiftUI
import DesignSystem

public struct MonthGrid: View {
    @Environment(\.palette) private var palette
    @Binding private var selection: Date?
    private let month: Date
    private let availableDays: Set<Date>   // дни со свободными слотами (startOfDay)
    private let myBookingDays: Set<Date>   // дни с моими тренировками (точка)
    private let calendar: Calendar

    public init(month: Date, selection: Binding<Date?>, availableDays: Set<Date>,
                myBookingDays: Set<Date>, calendar: Calendar = .current) {
        self.month = month
        self._selection = selection
        self.availableDays = availableDays
        self.myBookingDays = myBookingDays
        self.calendar = calendar
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Пустые ячейки до первого дня + все дни месяца.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: leading) + days
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 7), spacing: Space.xs) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol).font(.caption2).foregroundStyle(palette.textSecondary)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(minHeight: 44)
                }
            }
        }
        .padding(Space.s)
        .glassCard()
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = selection.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isAvailable = availableDays.contains(day)
        return Button { selection = day } label: {
            Text(day, format: .dateTime.day())
                .font(.callout.monospacedDigit().weight(isSelected ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isSelected ? palette.onAccent : palette.textPrimary)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(palette.accent)
                    }
                }
                .overlay(alignment: .bottom) {
                    if myBookingDays.contains(day) {
                        Circle().fill(isSelected ? palette.onAccent : palette.accent)
                            .frame(width: 5, height: 5).padding(.bottom, 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.35)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityHint(isAvailable ? "Есть свободное время" : "Нет свободных слотов")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
