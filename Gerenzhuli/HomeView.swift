import SwiftData
import SwiftUI

// MARK: - 今日（首页，之前那版，不是时间线版）
// 问候语 + 三格数字 + 深墨绿早报大卡 + 「接下来」+「待处理」+「订阅」

struct HomeView: View {
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReminderItem.sortOrder) private var reminders: [ReminderItem]
    @Query(sort: \DayEvent.date) private var events: [DayEvent]
    @Query(sort: \Subscriber.expiry) private var subscribers: [Subscriber]
    @State private var showBriefing = false
    @State private var showSettings = false
    @State private var selectedTabForJump: GZTab?
    /// 待处理：正在展开的行（可多开）、正在显示名单的行、操作后的反馈文案。
    @State private var expandedAlertIDs: Set<String> = []
    @State private var listShownIDs: Set<String> = []
    @State private var actionNotes: [String: String] = [:]

    /// 待处理三条：由订阅数据实时算出（见 Store.pendingAlerts），不是写死的文案。
    private var pendingAlerts: [PendingAlert] {
        Store.pendingAlerts(from: subscribers)
    }

    private var todayEvents: [DayEvent] {
        events.filter { Calendar.current.isDateInToday($0.date) }
    }

    /// 未完成提醒：按日期升序，最近 5 条（语音新增的也按日期插进来，标题直接可见）。
    private var upcomingReminders: [ReminderItem] {
        reminders
            .filter { !$0.isDone }
            .sorted { $0.date < $1.date }
            .prefix(5)
            .map { $0 }
    }

    /// 「接下来」：今天全部（已过时间的也显示）+ 明天，最多 5 条。
    /// 不再用 `date >= now`——无明确时间的日程默认明天 09:00（见 VoiceConfirmView），
    /// 但已过时间的今天日程也不应刚保存就从首页消失。
    private var nextEvents: [DayEvent] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let dayAfterTomorrow = cal.date(byAdding: .day, value: 2, to: todayStart) ?? Date()
        return events
            .filter { $0.date >= todayStart && $0.date < dayAfterTomorrow }
            .sorted { $0.date < $1.date }
            .prefix(5)
            .map { $0 }
    }

    /// 待处理展开区里的操作：全部在首页原地完成，不跳页。
    /// 「去续费」「不续了」是真实写入（改到期日 / 改备注），写完后待处理卡片自动重算，
    /// 解决掉的那条会直接消失；「查看名单」在同一行下面展开名单，再点收起。
    private func handlePendingAction(_ action: PendingAlertAction, for alert: PendingAlert) {
        switch action.kind {
        case .renew:
            guard let id = alert.subjectID,
                  let sub = subscribers.first(where: { $0.id == id }) else { return }
            let newExpiry = withAnimation(GZ.spring) { store.renewSubscriber(sub, in: modelContext) }
            actionNotes[alert.id] = "已续费一个月，新到期日 \(newExpiry.gzString("yyyy-MM-dd"))。"
        case .markNotRenewing:
            guard let id = alert.subjectID,
                  let sub = subscribers.first(where: { $0.id == id }) else { return }
            withAnimation(GZ.spring) { store.markSubscriberNotRenewing(sub, in: modelContext) }
            actionNotes[alert.id] = "已记下不续，\(sub.name) 不会再出现在待处理里。"
        case .viewList:
            withAnimation(GZ.spring) {
                if listShownIDs.contains(alert.id) {
                    listShownIDs.remove(alert.id)
                } else {
                    listShownIDs.insert(alert.id)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 问候
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(greetingForNow())")
                            .font(.gzLargeTitle)
                            .foregroundStyle(Color.gzText)
                        Text(Date().gzString("M月d日 EEEE"))
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                    }
                    .padding(.top, 4)
                    .gzAppear(delay: 0)

                    // 三格数字：日程 4 / 提醒 6 / 已过期 1（由种子实时算出）
                    HStack(spacing: 0) {
                        StatCell(value: store.eventsTodayCount(from: events), label: "日程", color: .gzText)
                        Divider().frame(height: 32)
                        StatCell(value: store.pendingRemindersCount(from: reminders), label: "提醒", color: .gzText)
                        Divider().frame(height: 32)
                        StatCell(value: store.overdueCount(from: reminders), label: "已过期", color: .gzRed)
                    }
                    .padding(.vertical, 14)
                    .gzCardStyle()
                    .gzAppear(delay: 0.06)

                    // 早报大卡：深墨绿渐变，点查看进详情
                    Button { showBriefing = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("今日早报")
                                    .font(.gzCaption)
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("\(Date().gzMonthDay)早报 · 昨日\(Calendar.current.date(byAdding: .day, value: -1, to: Date())?.gzMonthDay ?? "")要闻")
                                    .font(.gzHeadline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("国内 / 国际 / 财经 / 科技 · 12 条")
                                    .font(.gzFootnote)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Text("查看")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .padding(16)
                        .background(GZ.briefingGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .gzPressable()
                    .buttonStyle(.plain)
                    .gzAppear(delay: 0.12)

                    // 接下来
                    VStack(alignment: .leading, spacing: 0) {
                        GZSectionHeader(title: "接下来")
                            .padding(.bottom, 8)
                        VStack(spacing: 0) {
                            ForEach(Array(nextEvents.enumerated()), id: \.element.id) { index, event in
                                HStack(spacing: 10) {
                                    Text(event.timeLabel)
                                        .font(.gzNumber)
                                        .foregroundStyle(Color.gzInkGreen2)
                                        .frame(width: 52, alignment: .leading)
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
                                if index < nextEvents.count - 1 {
                                    Divider().padding(.leading, 62)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .gzCardStyle()
                    }
                    .gzAppear(delay: 0.18)

                    // 提醒：未完成提醒的标题列表（按日期升序，最近 5 条），点一条进提醒页。
                    // 以前首页只有提醒数字，没有标题，语音新增的提醒只让数字 +1，看起来像没保存。
                    VStack(alignment: .leading, spacing: 0) {
                        GZSectionHeader(title: "提醒", trailing: "\(store.pendingRemindersCount(from: reminders)) 条未完成")
                            .padding(.bottom, 8)
                        VStack(spacing: 0) {
                            if upcomingReminders.isEmpty {
                                Text("没有未完成的提醒。")
                                    .font(.gzFootnote)
                                    .foregroundStyle(Color.gzSecondary)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(Array(upcomingReminders.enumerated()), id: \.element.id) { index, item in
                                    NavigationLink(value: GZTab.reminders) {
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(item.status == .overdue ? Color.gzRed : item.status == .inProgress ? Color.gzGreen : Color.gzTertiary)
                                                .frame(width: 8, height: 8)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title)
                                                    .font(.gzHeadline)
                                                    .foregroundStyle(Color.gzText)
                                                    .lineLimit(1)
                                                Text(item.dateStatusText)
                                                    .font(.gzFootnote)
                                                    .foregroundStyle(Color.gzSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Color.gzTertiary)
                                        }
                                        .padding(.vertical, 9)
                                    }
                                    .buttonStyle(.plain)
                                    .gzScrollFade()
                                    if index < upcomingReminders.count - 1 {
                                        Divider().padding(.leading, 18)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .gzCardStyle()
                    }
                    .gzAppear(delay: 0.21)

                    // 待处理：点任意一条在原地展开详情和操作，不跳页
                    VStack(alignment: .leading, spacing: 0) {
                        GZSectionHeader(title: "待处理")
                            .padding(.bottom, 8)
                        VStack(spacing: 0) {
                            if pendingAlerts.isEmpty {
                                Text("没有待处理事项。")
                                    .font(.gzFootnote)
                                    .foregroundStyle(Color.gzSecondary)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(Array(pendingAlerts.enumerated()), id: \.element.id) { index, alert in
                                    VStack(alignment: .leading, spacing: 0) {
                                        Button {
                                            withAnimation(GZ.spring) {
                                                if expandedAlertIDs.contains(alert.id) {
                                                    expandedAlertIDs.remove(alert.id)
                                                } else {
                                                    expandedAlertIDs.insert(alert.id)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: alert.icon)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(Color.gzAmber)
                                                    .frame(width: 26)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(alert.title)
                                                        .font(.gzHeadline)
                                                        .foregroundStyle(Color.gzText)
                                                    Text(alert.detail)
                                                        .font(.gzFootnote)
                                                        .foregroundStyle(Color.gzSecondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(Color.gzTertiary)
                                                    .rotationEffect(.degrees(expandedAlertIDs.contains(alert.id) ? 90 : 0))
                                                    .animation(GZ.spring, value: expandedAlertIDs.contains(alert.id))
                                            }
                                            .padding(.vertical, 9)
                                        }
                                        .buttonStyle(.plain)

                                        if expandedAlertIDs.contains(alert.id) {
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(alert.expandedDetail)
                                                    .font(.gzFootnote)
                                                    .foregroundStyle(Color.gzSecondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                HStack(spacing: 8) {
                                                    ForEach(Array(alert.actions.enumerated()), id: \.offset) { _, action in
                                                        Button { handlePendingAction(action, for: alert) } label: {
                                                            Text(action.label)
                                                                .font(.system(size: 12.5, weight: .semibold))
                                                                .foregroundStyle(Color.gzInkGreen2)
                                                                .padding(.horizontal, 13)
                                                                .padding(.vertical, 7)
                                                                .background(Color.gzInkGreen2.opacity(0.12))
                                                                .clipShape(Capsule())
                                                        }
                                                        .gzPressable()
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                                if listShownIDs.contains(alert.id) {
                                                    VStack(alignment: .leading, spacing: 0) {
                                                        ForEach(Array(alert.listEntries.enumerated()), id: \.offset) { entryIndex, entry in
                                                            HStack(spacing: 8) {
                                                                Text(entry.name)
                                                                    .font(.gzHeadline)
                                                                    .foregroundStyle(Color.gzText)
                                                                    .lineLimit(1)
                                                                Text(entry.line)
                                                                    .font(.gzFootnote)
                                                                    .foregroundStyle(Color.gzSecondary)
                                                                    .lineLimit(1)
                                                            }
                                                            .padding(.vertical, 6)
                                                            if entryIndex < alert.listEntries.count - 1 {
                                                                Divider()
                                                            }
                                                        }
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 4)
                                                    .background(Color.gzCard2)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                }
                                                if let note = actionNotes[alert.id] {
                                                    Text(note)
                                                        .font(.gzFootnote)
                                                        .foregroundStyle(Color.gzGreen)
                                                }
                                            }
                                            .padding(.leading, 36)
                                            .padding(.bottom, 10)
                                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                                        }

                                        if index < pendingAlerts.count - 1 {
                                            Divider().padding(.leading, 36)
                                        }
                                    }
                                    .gzListTransition()
                                    .gzScrollFade()
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .gzCardStyle()
                        .animation(GZ.spring, value: expandedAlertIDs)
                    }
                    .gzAppear(delay: 0.24)

                    // 订阅卡：月收入由订阅行实时加总 + 三平台拆分
                    VStack(alignment: .leading, spacing: 0) {
                        GZSectionHeader(title: "订阅")
                            .padding(.bottom, 8)
                        NavigationLink(value: GZTab.subscribers) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(Store.monthlyTotal(from: subscribers).cny)
                                        .font(.gzNumberLarge)
                                        .foregroundStyle(Color.gzText)
                                    Text("/ 月")
                                        .font(.gzFootnote)
                                        .foregroundStyle(Color.gzSecondary)
                                    Spacer()
                                    Text("\(subscribers.count) 位在用")
                                        .font(.gzFootnote)
                                        .foregroundStyle(Color.gzSecondary)
                                }
                                HStack(spacing: 14) {
                                    ForEach(Store.monthlySplit(from: subscribers), id: \.0) { platform, amount in
                                        HStack(spacing: 4) {
                                            Circle().fill(platform.color).frame(width: 7, height: 7)
                                            Text("\(platform.shortTitle) \(amount.cny)")
                                                .font(.gzFootnote)
                                                .foregroundStyle(Color.gzSecondary)
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .gzCardStyle()
                        }
                        .buttonStyle(.plain)
                    }
                    .gzAppear(delay: 0.3)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.gzBackground)
            .navigationDestination(for: GZTab.self) { tab in
                if tab == .subscribers { SubscribersView() }
                else if tab == .reminders { RemindersView() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .gzPressable()
                    .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showBriefing) {
                BriefingView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}
