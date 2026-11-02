// BookingKit/Sources/BookingUI/StudentCalendarView.swift
import SwiftUI
import CoreDomain
import BookingDomain
import DesignSystem

public struct StudentCalendarView: View {
    @State private var viewModel: SlotPickerViewModel     // раздел 5.2.9
    @State private var selectedDay: Date?
    @Namespace private var slotNamespace
    let month: DateInterval
    let myBookingDays: Set<Date>

    public init(viewModel: SlotPickerViewModel, month: DateInterval, myBookingDays: Set<Date>) {
        _viewModel = State(initialValue: viewModel)
        self.month = month
        self.myBookingDays = myBookingDays
    }

    public var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                MonthGrid(month: month.start, selection: $selectedDay,
                          availableDays: Set(vm.slotsByDay.keys), myBookingDays: myBookingDays)

                if let day = selectedDay {
                    Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: Space.s) {
                        ForEach(vm.slotsByDay[day] ?? []) { slot in
                            let isSelected = vm.selectedSlot?.id == slot.id
                            Button { withAnimation(.spring(duration: 0.3)) { vm.select(slot) } } label: {
                                Text(slot.startsAt, format: .dateTime.hour().minute())
                                    .font(.callout.weight(.semibold).monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .glassCard(cornerRadius: Radius.m)
                            .matchedGeometryEffect(id: slot.id, in: slotNamespace, isSource: !isSelected)
                        }
                    }
                }
            }
            .padding(Space.l)
        }
        .safeAreaInset(edge: .bottom) {
            if let slot = vm.selectedSlot {
                Button { Task { await vm.book() } } label: {
                    Text("Записаться на \(slot.startsAt.formatted(.dateTime.hour().minute()))")
                }
                .buttonStyle(.cueGlassProminent)
                .disabled(vm.state == .booking)
                .padding(Space.l)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(ThemedBackground())
        .navigationTitle(Text(month.start, format: .dateTime.month(.wide)))
        .task { await vm.load(period: month) }
    }
}
