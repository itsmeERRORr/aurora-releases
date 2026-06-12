import SwiftUI

struct AuroraManualDatePicker: View {
    @Binding var selection: Date
    @State private var displayedMonth: Date
    @State private var hoveringDayID: String?

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.fixed(24), spacing: 3), count: 7)
    private let weekdaySymbols = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    init(selection: Binding<Date>) {
        _selection = selection
        _displayedMonth = State(initialValue: Calendar.autoupdatingCurrent.startOfMonth(for: selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(days, id: \.id) { day in
                    dayButton(day)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .onChange(of: selection) { _, newValue in
            let newMonth = calendar.startOfMonth(for: newValue)
            if !calendar.isDate(newMonth, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = newMonth
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(monthTitle)
                .font(.manrope(12, weight: .bold))
                .foregroundStyle(Color.auroraTxt)
            Spacer(minLength: 8)
            Button {
                moveMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(CalendarNavButtonStyle())
            Button {
                moveMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(CalendarNavButtonStyle())
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 3) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.manrope(9, weight: .bold))
                    .foregroundStyle(Color.auroraFaint.opacity(0.92))
                    .frame(width: 24)
            }
        }
    }

    private func dayButton(_ day: CalendarDay) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: selection)
        let isHovered = hoveringDayID == day.id

        return Button {
            selection = day.date
        } label: {
            Text("\(calendar.component(.day, from: day.date))")
                .font(.manrope(10, weight: isSelected || isHovered ? .bold : .semibold))
                .foregroundStyle(dayForeground(isCurrentMonth: day.isCurrentMonth, isSelected: isSelected, isHovered: isHovered))
                .frame(width: 24, height: 20)
                .background(dayBackground(isSelected: isSelected, isHovered: isHovered))
                .scaleEffect(isHovered && !isSelected ? 1.08 : 1)
                .shadow(color: isHovered || isSelected ? Color.auroraCyan.opacity(0.45) : .clear, radius: 6, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveringDayID = hovering ? day.id : nil
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

    private func dayForeground(isCurrentMonth: Bool, isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return .white }
        if isHovered { return .auroraCyan }
        return isCurrentMonth ? .auroraTxt : Color.auroraFaint.opacity(0.34)
    }

    @ViewBuilder
    private func dayBackground(isSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.auroraCyan, .auroraViolet, .auroraMagenta],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else if isHovered {
            Circle()
                .fill(Color.auroraCyan.opacity(0.14))
                .overlay(Circle().strokeBorder(Color.auroraCyan.opacity(0.8), lineWidth: 1))
        } else {
            Circle().fill(Color.clear)
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var days: [CalendarDay] {
        let monthStart = calendar.startOfMonth(for: displayedMonth)
        let weekday = calendar.component(.weekday, from: monthStart)
        let mondayBasedOffset = (weekday + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -mondayBasedOffset, to: monthStart) else { return [] }

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return CalendarDay(
                date: date,
                isCurrentMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month),
                calendar: calendar
            )
        }
    }

    private func moveMonth(_ offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = calendar.startOfMonth(for: month)
    }
}

private struct CalendarDay {
    let date: Date
    let isCurrentMonth: Bool
    let id: String

    init(date: Date, isCurrentMonth: Bool, calendar: Calendar) {
        self.date = date
        self.isCurrentMonth = isCurrentMonth
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        id = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct CalendarNavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.white : Color.auroraFaint)
            .frame(width: 17, height: 17)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.auroraCyan.opacity(0.2) : Color.clear)
            )
            .contentShape(Circle())
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
