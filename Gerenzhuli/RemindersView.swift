import SwiftData
import SwiftUI

// MARK: - 提醒事项：竖向时间线
// 顶部深色「结论」卡（自动汇总最先要做的两件），下面左侧圆形节点加竖线串联；
// 每项标题 + 日期·状态 + 一行灰色小字；点节点可勾选完成 / 取消，结论卡和首页数字同步变。

struct RemindersView: View {
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReminderItem.sortOrder) private var reminders: [ReminderItem]
    @State private var showAdd = false

    /// 今天 → 明天 → 稍后 → 已完成（时间线顺序）
    private var ordered: [ReminderItem] {
        let cal = Calendar.current
        func rank(_ item: ReminderItem) -> Int {
            if item.isDone { return 3 }
            if item.status == .overdue { return 0 }
            if cal.isDateInToday(item.date) { return 0 }
            if cal.isDateInTomorrow(item.date) { return 1 }
            return 2
        }
        return reminders.sorted {
            let r0 = rank($0), r1 = rank($1)
            if r0 != r1 { return r0 < r1 }
            return $0.date < $1.date
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 结论卡：深色
                    VStack(alignment: .leading, spacing: 4) {
                        Text("结论")
                            .font(.gzCaption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(store.conclusion(for: reminders))
                            .font(.gzHeadline)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GZ.briefingGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .gzAppear(delay: 0)

                    // 时间线
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, item in
                            TimelineRow(
                                title: item.title,
                                meta: item.dateStatusText,
                                detail: item.detail,
                                status: item.status,
                                isLast: index == ordered.count - 1,
                                onTapNode: {
                                    withAnimation(GZ.spring) { store.toggle(item) }
                                }
                            )
                            .opacity(item.isDone ? 0.55 : 1.0)
                            .animation(GZ.spring, value: item.isDone)
                            .sensoryFeedback(.impact(weight: .light), trigger: item.isDone)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.gzBackground)
            .navigationTitle("提醒事项")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .gzPressable()
                }
            }
            .sheet(isPresented: $showAdd) {
                AddReminderView()
            }
        }
    }
}

// MARK: - 新建提醒

struct AddReminderView: View {
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $title)
                        .font(.gzBody)
                    TextField("一句话说明（可选）", text: $detail)
                        .font(.gzBody)
                }
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .font(.gzBody)
                }
            }
            .navigationTitle("新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.addReminder(title: trimmed, detail: detail, date: date, in: modelContext)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
