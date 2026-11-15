import SwiftData
import SwiftUI

// MARK: - 日历：日 / 周视图切换，点日期看当天日程

enum CalendarMode: String, CaseIterable {
    case day, week

    var title: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        }
    }
}

struct CalendarView: View {
    @Query(sort: \DayEvent.date) private var events: [DayEvent]
    @State private var mode: CalendarMode = .week
    @State private var selectedDate = Date()
    @State private var weekOffset = 0
    /// 选中日期环的共享几何：点新日期时圆环滑过去，不生硬跳变
    @Namespace private var dayRing

    private var calendar: Calendar { Calendar.current }

    private var weekDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        let base = calendar.date(byAdding: .day, value: weekOffset * 7, to: today) ?? today
        let weekday = calendar.component(.weekday, from: base)
        // 以周一为一周开始
        let startOffset = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -startOffset, to: base) ?? base
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var selectedEvents: [DayEvent] {
        events.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date < $1.date }
    }

    private func hasEvent(on date: Date) -> Bool {
        events.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // 标题 + 日/周切换
                HStack {
                    Text(selectedDate.gzString("M月"))
                        .font(.gzLargeTitle)
                        .foregroundStyle(Color.gzText)
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(CalendarMode.allCases, id: \.self) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 96)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                if mode == .week {
                    // 周视图：一行 7 天（选中环用 matchedGeometryEffect 滑到新日期）
                    HStack(spacing: 0) {
                        ForEach(weekDays, id: \.self) { day in
                            Button { withAnimation(GZ.spring) { selectedDate = day } } label: {
                                VStack(spacing: 5) {
                                    Text(day.gzString("EEE"))
                                        .font(.gzCaption)
                                        .foregroundStyle(Color.gzSecondary)
                                    Text("\(calendar.component(.day, from: day))")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? .white : Color.gzText)
                                        .frame(width: 34, height: 34)
                                        .background {
                                            if calendar.isDate(day, inSameDayAs: selectedDate) {
                                                Circle()
                                                    .fill(Color.gzInkGreen2)
                                                    .matchedGeometryEffect(id: "selectedDay", in: dayRing)
                                            }
                                        }
                                    Circle()
                                        .fill(hasEvent(on: day) ? Color.gzInkGreen2 : Color.clear)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .gzPressable()
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .animation(GZ.spring, value: selectedDate)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    HStack {
                        Button { withAnimation(GZ.spring) { weekOffset -= 1 } } label: {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        }
                        .gzPressable()
                        Spacer()
                        Button("回到今天") { withAnimation(GZ.spring) { weekOffset = 0; selectedDate = Date() } }
                            .font(.gzFootnote)
                            .gzPressable()
                        Spacer()
                        Button { withAnimation(GZ.spring) { weekOffset += 1 } } label: {
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        }
                        .gzPressable()
                    }
                    .foregroundStyle(Color.gzSecondary)
                    .padding(.horizontal, 16)
                } else {
                    // 日视图：当天大日期 + 小时线
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(calendar.component(.day, from: selectedDate))")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Color.gzText)
                        Text(selectedDate.gzString("EEEE · yyyy年M月d日"))
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color.gzInkGreen2)
                        .padding(.horizontal, 8)
                }

                // 当天日程
                VStack(alignment: .leading, spacing: 8) {
                    GZSectionHeader(title: selectedDate.gzString("M月d日") + " · 日程", trailing: "\(selectedEvents.count) 场")
                    if selectedEvents.isEmpty {
                        Text("这一天没有安排。")
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gzCardStyle()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(selectedEvents.enumerated()), id: \.element.id) { index, event in
                                HStack(spacing: 10) {
                                    Text(event.timeLabel)
                                        .font(.gzNumber)
                                        .foregroundStyle(Color.gzInkGreen2)
                                        .frame(width: 64, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .font(.gzHeadline)
                                            .foregroundStyle(Color.gzText)
                                        if !event.note.isEmpty {
                                            Text(event.note)
                                                .font(.gzFootnote)
                                                .foregroundStyle(Color.gzSecondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                                .gzScrollFade()
                                if index < selectedEvents.count - 1 {
                                    Divider().padding(.leading, 74)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .gzCardStyle()
                        .gzListTransition()
                    }
                }
                .padding(.horizontal, 16)
                .animation(GZ.spring, value: selectedDate)

                Spacer()
            }
            .animation(GZ.spring, value: mode)
            .background(Color.gzBackground)
        }
    }
}
