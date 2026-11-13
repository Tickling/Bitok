// BookingKit/Sources/BookingUI/CoachCalendarView.swift
import SwiftUI
import CoreDomain
import BookingDomain
import DesignSystem

public struct CoachScheduleEntry: Identifiable, Hashable, Sendable {
    public init(id: UUID, startsAt: Date, durationMinutes: Int, status: BookingStatus?, studentId: UserID?,
                studentName: String?, studentPhone: String?) {
        self.id = id
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.status = status
        self.studentId = studentId
        self.studentName = studentName
        self.studentPhone = studentPhone
    }

    public let id: UUID
    public let startsAt: Date
    public let durationMinutes: Int
    public let status: BookingStatus?          // nil — свободный слот
    public let studentId: UserID?
    public let studentName: String?
    public let studentPhone: String?           // приходит из BFF только тренеру этого ученика
}

public struct CoachCalendarView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case day = "День", week = "Неделя", month = "Месяц"
        var id: Self { self }
    }

    @Environment(\.palette) private var palette
    @State private var mode: Mode = .day
    let entries: [CoachScheduleEntry]
    let onOpenStudent: (UserID) -> Void
    let onCreateSlot: (Date) -> Void

    public init(entries: [CoachScheduleEntry], onOpenStudent: @escaping (UserID) -> Void,
                onCreateSlot: @escaping (Date) -> Void) {
        self.entries = entries
        self.onOpenStudent = onOpenStudent
        self.onCreateSlot = onCreateSlot
    }

    public var body: some View {
        VStack(spacing: Space.m) {
            Picker("Режим", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .day:
                List(entries) { entry in
                    row(entry)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            case .week, .month:
                // Неделя — 7 колонок с полосами занятости; месяц — MonthGrid с числом записей в дне.
                Text("Сетки недели и месяца переиспользуют MonthGrid и DayColumn")
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, Space.l)
        .background(ThemedBackground())
    }

    @ViewBuilder
    private func row(_ entry: CoachScheduleEntry) -> some View {
        if let status = entry.status, let name = entry.studentName, let studentId = entry.studentId {
            HStack(spacing: Space.m) {
                RoundedRectangle(cornerRadius: 2).fill(color(for: status)).frame(width: 4)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("\(entry.startsAt.formatted(.dateTime.hour().minute())) · \(name)").font(.headline)
                    status.pill
                    if let phone = entry.studentPhone, let url = URL(string: "tel:\(phone)") {
                        Link(destination: url) { Label(phone, systemImage: "phone") }.font(.callout)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(palette.textSecondary)
            }
            .padding(Space.m)
            .glassCard()
            .contentShape(Rectangle())
            .onTapGesture { onOpenStudent(studentId) }
        } else {
            Button { onCreateSlot(entry.startsAt) } label: {
                Label("\(entry.startsAt.formatted(.dateTime.hour().minute())) · свободно — открыть слот", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.m)
                    .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                        .strokeBorder(palette.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.textSecondary)
        }
    }

    private func color(for status: BookingStatus) -> Color {
        switch status {
        case .awaitingCoachApproval, .draft: palette.statusPending
        case .awaitingPayment: palette.statusPayment
        case .confirmed: palette.statusConfirmed
        case .completed: palette.statusCompleted
        default: palette.statusCancelled
        }
    }
}
