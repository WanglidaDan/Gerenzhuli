import Foundation
import SwiftData
import SwiftUI

// MARK: - 全局数据（SwiftData 为准，Store 只做汇总与种子）

@Observable
final class Store {
    var modelContext: ModelContext?

    /// 订阅月收入：由当前订阅行的 priceMonthly 实时加总（不是写死的 926）。
    /// 注意：种子只有台账里的 15 位代表行，加总约 ¥312，不等于全量台账折合 ¥926；
    /// 上线换真实台账数据后，加总就是真实月收入。
    static func monthlyTotal(from subscribers: [Subscriber]) -> Int {
        subscribers.reduce(0) { $0 + $1.priceMonthly }
    }

    static func monthlySplit(from subscribers: [Subscriber]) -> [(Platform, Int)] {
        Platform.allCases.map { platform in
            (platform, subscribers.filter { $0.platform == platform }.reduce(0) { $0 + $1.priceMonthly })
        }
    }

    // MARK: 汇总（由调用方传入 @Query 的数组，保持纯函数、可测）

    /// 今日日程数（首页三格数字之一）
    func eventsTodayCount(from events: [DayEvent]) -> Int {
        events.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    /// 未完成提醒数（首页三格数字之一）
    func pendingRemindersCount(from reminders: [ReminderItem]) -> Int {
        reminders.filter { !$0.isDone }.count
    }

    /// 已逾期提醒数（首页三格数字之一）
    func overdueCount(from reminders: [ReminderItem]) -> Int {
        reminders.filter { $0.status == .overdue }.count
    }

    /// 结论卡：自动汇总最先要做的两件（未完成、按日期升序）
    func conclusion(for reminders: [ReminderItem]) -> String {
        let pending = reminders.filter { !$0.isDone }.sorted { $0.date < $1.date }
        guard let first = pending.first else { return "今天没有待办，可以歇一歇。" }
        if pending.count == 1 {
            return "现在只做一件：\(first.title)。"
        }
        let second = pending[1]
        let rest = pending.count - 2
        if rest > 0 {
            return "现在只做两件：\(first.title)，\(second.title)，其余 \(rest) 件排在后面。"
        }
        return "现在只做两件：\(first.title)，\(second.title)。"
    }

    // MARK: - 首页「待处理」：由订阅数据实时算出，不是写死的文案
    // 点一行在首页原地展开详情和操作，不跳页；「去续费」「不续了」是真实写入
    // （续费改到期日、不续改备注），写完后本卡片自动重算，解决掉的那条会消失。
    // 已取消（备注含“已取消”）的订阅不进待处理。

    static func pendingAlerts(from subscribers: [Subscriber]) -> [PendingAlert] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var alerts: [PendingAlert] = []

        // 1. 已过期：取最早过期的一位（已取消的不算）
        let expired = subscribers
            .filter { $0.status == .expired && !$0.note.contains("已取消") }
            .sorted { $0.expiry < $1.expiry }
        if let first = expired.first {
            alerts.append(PendingAlert(
                id: "expired",
                kind: .expired,
                icon: "exclamationmark.circle.fill",
                title: "\(first.name) 已过期",
                detail: "\(first.platform.title) · \(first.profile) · \(first.expiryText)",
                expandedDetail: "\(first.platform.title) · \(first.profile)资料，\(first.billingLabel)，\(first.expiryText) 到期。续还是不续，等你一句话。",
                actions: [
                    PendingAlertAction(kind: .renew, label: "去续费"),
                    PendingAlertAction(kind: .markNotRenewing, label: "不续了"),
                ],
                listEntries: [],
                subjectID: first.id
            ))
        }

        // 2. 未来 30 天内到期
        let upcoming = subscribers.filter {
            let day = cal.startOfDay(for: $0.expiry)
            guard day >= today else { return false }
            let days = cal.dateComponents([.day], from: today, to: day).day ?? 99
            return days <= 30
        }.sorted { $0.expiry < $1.expiry }
        if !upcoming.isEmpty {
            let dec34 = upcoming.filter {
                let c = cal.dateComponents([.month, .day], from: $0.expiry)
                return c.month == 12 && (c.day == 3 || c.day == 4)
            }.count
            alerts.append(PendingAlert(
                id: "expiringSoon",
                kind: .expiringSoon,
                icon: "clock.fill",
                title: "\(upcoming.count) 人将到期",
                detail: "12 月 3–4 日集中到期",
                expandedDetail: "未来 30 天内有 \(upcoming.count) 位到期，其中 12 月 3–4 日最集中，有 \(dec34) 位。",
                actions: [PendingAlertAction(kind: .viewList, label: "查看名单")],
                listEntries: upcoming.map { ($0.name, "\($0.platform.title) · \($0.profile) · 到期 \($0.expiryText) · \($0.billingLabel)") },
                subjectID: nil
            ))
        }

        // 3. 资料超员：同一资料超过 2 人上限
        let fengzhi = subscribers
            .filter { $0.profile == "风之骄子" }
            .sorted { $0.expiry < $1.expiry }
        if fengzhi.count > 2 {
            let names = fengzhi.map { $0.name }.joined(separator: "、")
            alerts.append(PendingAlert(
                id: "overCapacity",
                kind: .overCapacity,
                icon: "person.2.fill",
                title: "风之骄子超员",
                detail: "已有 \(fengzhi.count) 人在用，超过 2 人上限",
                expandedDetail: "风之骄子资料已有 \(fengzhi.count) 人在用（\(names)），超过 2 人上限，别再往里加人。",
                actions: [PendingAlertAction(kind: .viewList, label: "查看名单")],
                listEntries: fengzhi.map { ($0.name, "\($0.platform.title) · 到期 \($0.expiryText) · \($0.billingLabel)") },
                subjectID: nil
            ))
        }

        return alerts
    }

    // MARK: 变更

    func toggle(_ reminder: ReminderItem) {
        reminder.isDone.toggle()
        try? modelContext?.save()
    }

    /// 待处理「去续费」：到期日从今天起顺延一个月（避免按已过期日顺延越续越早），备注不动。
    /// 返回新的到期日；写完后首页待处理卡片自动重算。
    func renewSubscriber(_ sub: Subscriber, in context: ModelContext) -> Date {
        let base = max(sub.expiry, Date())
        let newExpiry = Calendar.current.date(byAdding: .month, value: 1, to: base) ?? base
        sub.expiry = newExpiry
        try? context.save()
        return newExpiry
    }

    /// 待处理「不续了」：备注改成“已取消，不续”，该订阅不再进待处理（不删除记录）。
    func markSubscriberNotRenewing(_ sub: Subscriber, in context: ModelContext) {
        sub.note = "已取消，不续"
        try? context.save()
    }

    /// 保存失败返回 false（调用方要如实报错，不要显示“已添加”）。
    /// sortOrder 按日期排：新提醒插到日期顺序里，不再永远排最后。
    @discardableResult
    func addReminder(title: String, detail: String, date: Date, in context: ModelContext) -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<ReminderItem>(sortBy: [SortDescriptor(\.date)]))) ?? []
        var order = 0
        for item in existing {
            if item.date < date { order += 1 } else { item.sortOrder += 1 }
        }
        let item = ReminderItem(title: title, detail: detail, date: date, icon: "checklist", sortOrder: order)
        context.insert(item)
        do {
            try context.save()
            return true
        } catch {
            context.delete(item)
            return false
        }
    }

    /// 语音解析写入：新建日程（timeLabel 由日期生成，如“15:00”）。
    @discardableResult
    func addEvent(title: String, note: String, date: Date, in context: ModelContext) -> Bool {
        let event = DayEvent(title: title, timeLabel: date.gzString("HH:mm"), date: date, note: note, icon: "calendar")
        context.insert(event)
        do {
            try context.save()
            return true
        } catch {
            context.delete(event)
            return false
        }
    }

    /// 语音解析写入：新建订阅。资料、价格未知时写“待确认 / 价格待定”，由用户在确认卡上改。
    @discardableResult
    func addSubscriber(name: String, profile: String, platform: Platform, priceMonthly: Int,
                       billingLabel: String, expiry: Date, note: String, in context: ModelContext) -> Bool {
        let sub = Subscriber(name: name, profile: profile, platform: platform,
                             priceMonthly: priceMonthly, billingLabel: billingLabel, expiry: expiry, note: note)
        context.insert(sub)
        do {
            try context.save()
            return true
        } catch {
            context.delete(sub)
            return false
        }
    }

    // MARK: 出行

    func addTrip(_ trip: Trip, in context: ModelContext) {
        context.insert(trip)
        try? context.save()
    }

    func deleteTrip(_ trip: Trip, in context: ModelContext) {
        context.delete(trip)
        try? context.save()
    }

    func addTicket(_ ticket: TripTicket, to trip: Trip, in context: ModelContext) {
        trip.tickets.append(ticket)
        try? context.save()
    }

    // MARK: 种子数据（首次打开时写入；上线前替换为真实数据源，见 Models.swift 的 TODO）

    func seedIfNeeded(context: ModelContext) {
        self.modelContext = context
        let existing = (try? context.fetchCount(FetchDescriptor<ReminderItem>())) ?? 0
        if existing > 0 { return }
        Seed.load(into: context)
    }
}

// MARK: - 种子

enum Seed {
    static func fixedDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func relativeDay(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func load(into context: ModelContext) {
        // ---- 提醒事项：未完成 6 条（含已逾期 1 条）+ 已完成 1 条 ----
        let reminders: [ReminderItem] = [
            ReminderItem(title: "追流媒体续费", detail: "12 月 3–4 日 17 条集中到期，11 月 30 日前提醒一次", date: relativeDay(-1, hour: 9), icon: "clock.fill", sortOrder: 0),
            ReminderItem(title: "核实备份失败邮件来源", detail: "阿里云快照通知，待核对发件邮箱", date: relativeDay(0, hour: 22, minute: 30), icon: "envelope.fill", sortOrder: 1),
            ReminderItem(title: "定格开屏 v2 首启验收", detail: "装好 TestFlight 1.0.0 后第一时间打开看", date: relativeDay(0, hour: 21), icon: "camera.fill", sortOrder: 2),
            ReminderItem(title: "给悠呆发专属接码链接", detail: "Netflix QQ 资料，12 月 3 日到期", date: relativeDay(1, hour: 10), icon: "link", sortOrder: 3),
            ReminderItem(title: "k 的 Disney+ 续还是不续", detail: "16 元/月，已过期，等你一句话", date: relativeDay(1, hour: 18), icon: "play.tv.fill", sortOrder: 4),
            ReminderItem(title: "好名字到期前 3 天提醒", detail: "2027 年 1 月 27 日，到期前 3 天", date: fixedDate(2027, 1, 27), icon: "bell.fill", sortOrder: 5),
            ReminderItem(title: "sansen HBO 延期核实", detail: "已续到 2027-01-11，无需再延", date: relativeDay(-4, hour: 17), isDone: true, icon: "checkmark.circle.fill", sortOrder: 6),
        ]
        reminders.forEach { context.insert($0) }

        // ---- 当日日程：今天 4 场 ----
        let events: [DayEvent] = [
            DayEvent(title: "每日早报", timeLabel: "08:10", date: relativeDay(0, hour: 8, minute: 10), note: "国内 / 国际 / 财经 / 科技", icon: "newspaper.fill"),
            DayEvent(title: "客户拍摄沟通", timeLabel: "09:30", date: relativeDay(0, hour: 9, minute: 30), note: "档期与成片交付", icon: "camera.fill"),
            DayEvent(title: "定格开屏 v2 首启验收", timeLabel: "21:00", date: relativeDay(0, hour: 21), note: "TestFlight 1.0.0", icon: "checkmark.circle.fill"),
            DayEvent(title: "核实备份失败邮件来源", timeLabel: "22:30", date: relativeDay(0, hour: 22, minute: 30), note: "阿里云快照通知", icon: "envelope.fill"),
            DayEvent(title: "明日早报", timeLabel: "明天 08:10", date: relativeDay(1, hour: 8, minute: 10), note: "定时推送", icon: "newspaper.fill"),
        ]
        events.forEach { context.insert($0) }

        // ---- 流媒体订阅：15 位台账种子（姓名、资料、到期日、价格均为台账实查） ----
        // 价格为台账价：月付按月价，年付 / 季付按 billingLabel 原样写，priceMonthly 为折合月价。
        let subscribers: [Subscriber] = [
            Subscriber(name: "k", profile: "风之骄子", platform: .disney, priceMonthly: 16, billingLabel: "16元/月", expiry: fixedDate(2026, 11, 12), note: "续还是不续待定"),
            Subscriber(name: "M", profile: "Gmail", platform: .netflix, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2026, 11, 30)),
            Subscriber(name: "Mark Soo", profile: "Gmail", platform: .netflix, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2026, 12, 1)),
            Subscriber(name: "小拾檀记", profile: "Gmail", platform: .hbo, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2026, 12, 1)),
            Subscriber(name: "悠呆", profile: "清风明月", platform: .netflix, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2026, 12, 3)),
            Subscriber(name: "funglam", profile: "星野旅人", platform: .netflix, priceMonthly: 25, billingLabel: "25元/月 · 电视", expiry: fixedDate(2026, 12, 3)),
            Subscriber(name: "小周小周招呼不周", profile: "QQ", platform: .netflix, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2026, 12, 3)),
            Subscriber(name: "PG永胜", profile: "云边小驻", platform: .netflix, priceMonthly: 30, billingLabel: "30元/月 · 电视", expiry: fixedDate(2026, 12, 4)),
            Subscriber(name: "nioko", profile: "一盏青灯", platform: .netflix, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2026, 12, 4)),
            Subscriber(name: "sansen", profile: "Gmail", platform: .hbo, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2027, 1, 11)),
            Subscriber(name: "好名字更容易让朋友记住你", profile: "Gmail", platform: .netflix, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2027, 1, 30), note: "不恢复链接"),
            Subscriber(name: "小翁同学", profile: "风之骄子", platform: .netflix, priceMonthly: 20, billingLabel: "60元/季", expiry: fixedDate(2027, 2, 1)),
            Subscriber(name: "虾花钳", profile: "风之骄子", platform: .netflix, priceMonthly: 20, billingLabel: "240元/年", expiry: fixedDate(2027, 7, 27)),
            Subscriber(name: "吃饭了", profile: "风之骄子", platform: .netflix, priceMonthly: 21, billingLabel: "21元/月 · 年付 252 元", expiry: fixedDate(2027, 11, 13)),
            Subscriber(name: "bilin", profile: "QQ", platform: .hbo, priceMonthly: 20, billingLabel: "20元/月", expiry: fixedDate(2026, 11, 10), note: "已取消，不续"),
        ]
        subscribers.forEach { context.insert($0) }

        // ---- 出行：两条行程种子（大庆出发，日期均为示例） ----
        let trips: [Trip] = [
            Trip(title: "香港三日", destination: "香港", departDate: fixedDate(2026, 12, 4), returnDate: fixedDate(2026, 12, 6),
                 transport: "大庆 – 北京 – 香港，飞机", stay: "香港岛酒店 2 晚", note: "示例行程：出发、交通、住宿、地点按时间排"),
            Trip(title: "潮州寻味", destination: "潮州", departDate: fixedDate(2027, 1, 16), returnDate: fixedDate(2027, 1, 18),
                 transport: "高铁 + 市内打车", stay: "古城民宿 2 晚", note: "示例行程"),
        ]
        trips.forEach { context.insert($0) }
        trips[0].stops = [
            TripStop(kind: .departure, title: "大庆出发", timeLabel: "12月4日 08:00", detail: "大庆萨尔图机场，提前 2 小时到", sortOrder: 0),
            TripStop(kind: .transport, title: "北京转机", timeLabel: "12月4日 12:30", detail: "转机 1 小时 40 分，别出安检", sortOrder: 1),
            TripStop(kind: .place, title: "维港夜景", timeLabel: "12月4日 19:00", detail: "尖沙咀海滨，带脚架", sortOrder: 2),
            TripStop(kind: .stay, title: "入住香港岛酒店", timeLabel: "12月4日 21:00", detail: "前台取房卡，押金刷卡", sortOrder: 3),
            TripStop(kind: .place, title: "中环半山扶梯", timeLabel: "12月5日 10:00", detail: "拍照 + 咖啡", sortOrder: 4),
            TripStop(kind: .departure, title: "返程", timeLabel: "12月6日 15:00", detail: "香港 – 北京 – 大庆", sortOrder: 5),
        ]
        trips[0].tickets = [
            TripTicket(kind: .flight, title: "大庆 – 香港往返机票", code: "CZ3101 / CZ3102", price: 1880, statusText: "已出票"),
            TripTicket(kind: .ticket, title: "太平山顶缆车票", code: "电子票", price: 88, statusText: "待使用"),
        ]
        trips[1].stops = [
            TripStop(kind: .departure, title: "出发去潮州", timeLabel: "1月16日 07:30", detail: "高铁站集合", sortOrder: 0),
            TripStop(kind: .place, title: "牌坊街", timeLabel: "1月16日 14:00", detail: "逛吃拍照", sortOrder: 1),
            TripStop(kind: .stay, title: "入住古城民宿", timeLabel: "1月16日 18:00", detail: "古城内，步行可达", sortOrder: 2),
            TripStop(kind: .place, title: "广济桥", timeLabel: "1月17日 09:00", detail: "早上光线好，拍桥", sortOrder: 3),
        ]
        trips[1].tickets = [
            TripTicket(kind: .ticket, title: "广济桥门票", code: "电子票", price: 60, statusText: "待使用"),
        ]

        // ---- 早报：12 项占位，格式与定版一致，内容一律「待生成」，不编造新闻 ----
        var order = 1
        var items: [BriefingItem] = []
        for section in BriefingSection.allCases {
            for _ in 0..<3 {
                items.append(BriefingItem(section: section, keyword: "待生成", summary: "待生成", source: "待生成", order: order))
                order += 1
            }
        }
        items.forEach { context.insert($0) }

        try? context.save()
    }
}
