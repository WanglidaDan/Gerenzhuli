import Foundation
import SwiftData
import SwiftUI

// MARK: - 平台

enum Platform: String, Codable, CaseIterable {
    case netflix, hbo, disney

    var title: String {
        switch self {
        case .netflix: return "Netflix"
        case .hbo: return "HBO Max"
        case .disney: return "Disney+"
        }
    }

    var shortTitle: String {
        switch self {
        case .netflix: return "奈飞"
        case .hbo: return "HBO"
        case .disney: return "迪士尼"
        }
    }

    var color: Color {
        switch self {
        case .netflix: return Color(hex: 0xE50914)
        case .hbo: return Color(hex: 0x7B5CFF)
        case .disney: return Color(hex: 0x0A84FF)
        }
    }
}

// MARK: - 提醒状态（由日期 + 是否完成推导，不另存）

enum ReminderStatus {
    case done, overdue, inProgress, upcoming

    var title: String {
        switch self {
        case .done: return "已完成"
        case .overdue: return "已逾期"
        case .inProgress: return "进行中"
        case .upcoming: return "接下来"
        }
    }
}

// MARK: - 提醒事项（SwiftData）

@Model
final class ReminderItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var detail: String
    var date: Date
    var isDone: Bool
    var icon: String
    var sortOrder: Int

    init(title: String, detail: String, date: Date, isDone: Bool = false, icon: String = "checklist", sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.date = date
        self.isDone = isDone
        self.icon = icon
        self.sortOrder = sortOrder
    }

    var status: ReminderStatus {
        if isDone { return .done }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        if day < today { return .overdue }
        if cal.isDateInToday(date) { return .inProgress }
        return .upcoming
    }

    /// “11月16日 · 进行中”
    var dateStatusText: String {
        "\(date.gzString("M月d日")) · \(status.title)"
    }
}

// MARK: - 当日日程（SwiftData）

@Model
final class DayEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var timeLabel: String
    var date: Date
    var note: String
    var icon: String

    init(title: String, timeLabel: String, date: Date, note: String = "", icon: String = "calendar") {
        self.id = UUID()
        self.title = title
        self.timeLabel = timeLabel
        self.date = date
        self.note = note
        self.icon = icon
    }
}

// MARK: - 流媒体订阅（SwiftData）
// TODO(真实数据): 把 Seed 里的 15 行换成 Notion 台账 / 取码系统接口拉取的真实订阅；
// 姓名、资料、到期日、价格以台账为准，月收入由订阅行实时加总（见 Store.monthlyTotal），
// 不是写死的数；种子只有 15 行，加总不等于全量台账折合 ¥926。

enum SubscriberStatus {
    case expired, expiringSoon, active

    var title: String {
        switch self {
        case .expired: return "已过期"
        case .expiringSoon: return "将到期"
        case .active: return "在用"
        }
    }

    var color: Color {
        switch self {
        case .expired: return .gzRed
        case .expiringSoon: return .gzAmber
        case .active: return .gzGreen
        }
    }
}

@Model
final class Subscriber {
    @Attribute(.unique) var id: UUID
    var name: String
    var profile: String
    var platformRaw: String
    var priceMonthly: Int
    var billingLabel: String
    var expiry: Date
    var note: String

    init(name: String, profile: String, platform: Platform, priceMonthly: Int, billingLabel: String, expiry: Date, note: String = "") {
        self.id = UUID()
        self.name = name
        self.profile = profile
        self.platformRaw = platform.rawValue
        self.priceMonthly = priceMonthly
        self.billingLabel = billingLabel
        self.expiry = expiry
        self.note = note
    }

    var platform: Platform { Platform(rawValue: platformRaw) ?? .netflix }

    var status: SubscriberStatus {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: expiry)
        if day < today { return .expired }
        let days = cal.dateComponents([.day], from: today, to: day).day ?? 99
        if days <= 7 { return .expiringSoon }
        return .active
    }

    /// “2026-12-03”
    var expiryText: String { expiry.gzString("yyyy-MM-dd") }
}

// MARK: - 首页「待处理」展开项（点一行在首页原地展开，不跳页）

enum PendingAlertKind: String {
    case expired, expiringSoon, overCapacity
}

struct PendingAlertAction {
    enum Kind { case renew, markNotRenewing, viewList }
    let kind: Kind
    let label: String
}

struct PendingAlert: Identifiable {
    let id: String
    let kind: PendingAlertKind
    let icon: String
    let title: String
    let detail: String
    let expandedDetail: String
    let actions: [PendingAlertAction]
    /// “查看名单”展开时列出的人（名字 + 一行说明）。
    let listEntries: [(name: String, line: String)]
    /// 关联的订阅（去续费 / 不续了的操作对象，仅“已过期”那条有）。
    let subjectID: UUID?
}

// MARK: - 出行（SwiftData）
// 一次行程 = 出发 + 交通 + 住宿 + 要去的地方，按时间排；机票 / 门票 / 订单挂在行程下面。
// 地点导航走 MapKit（打开苹果地图），票证进钱包是占位（待接 PassKit），行程配图走 Photos（PHPicker）。
// TODO(真实数据): 订票查价比价接真实票务接口后，把 TripTicket.priceOptions 换成接口返回的实时报价；
// 导航的经纬度用地名反编码（CLGeocoder）后存进 TripStop，替代现在只存地名字符串的做法。

enum TripStatus {
    case upcoming, ongoing, done

    var title: String {
        switch self {
        case .upcoming: return "即将出发"
        case .ongoing: return "进行中"
        case .done: return "已完成"
        }
    }

    var color: Color {
        switch self {
        case .upcoming: return .gzBlue
        case .ongoing: return .gzGreen
        case .done: return .gzSecondary
        }
    }
}

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var title: String
    var destination: String
    var departDate: Date
    var returnDate: Date
    var transport: String
    var stay: String
    var note: String
    @Relationship(deleteRule: .cascade) var stops: [TripStop] = []
    @Relationship(deleteRule: .cascade) var tickets: [TripTicket] = []

    init(title: String, destination: String, departDate: Date, returnDate: Date,
         transport: String = "", stay: String = "", note: String = "") {
        self.id = UUID()
        self.title = title
        self.destination = destination
        self.departDate = departDate
        self.returnDate = returnDate
        self.transport = transport
        self.stay = stay
        self.note = note
    }

    var status: TripStatus {
        let today = Calendar.current.startOfDay(for: Date())
        if today > Calendar.current.startOfDay(for: returnDate) { return .done }
        if today >= Calendar.current.startOfDay(for: departDate) { return .ongoing }
        return .upcoming
    }

    /// “11月20日 – 11月23日”
    var dateRangeText: String {
        "\(departDate.gzMonthDay) – \(returnDate.gzMonthDay)"
    }
}

/// 行程里的一站：出发 / 交通 / 住宿 / 要去的地方，按时间排。
enum TripStopKind: String, Codable, CaseIterable {
    case departure, transport, stay, place

    var title: String {
        switch self {
        case .departure: return "出发"
        case .transport: return "交通"
        case .stay: return "住宿"
        case .place: return "要去的地方"
        }
    }

    var icon: String {
        switch self {
        case .departure: return "airplane.departure"
        case .transport: return "car.fill"
        case .stay: return "bed.double.fill"
        case .place: return "mappin.and.ellipse"
        }
    }
}

@Model
final class TripStop {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var timeLabel: String
    var detail: String
    var sortOrder: Int

    init(kind: TripStopKind, title: String, timeLabel: String, detail: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.timeLabel = timeLabel
        self.detail = detail
        self.sortOrder = sortOrder
    }

    var kind: TripStopKind { TripStopKind(rawValue: kindRaw) ?? .place }
}

/// 挂在行程下面的票 / 订单：机票、门票、酒店订单。
enum TripTicketKind: String, Codable, CaseIterable {
    case flight, ticket, hotel

    var title: String {
        switch self {
        case .flight: return "机票"
        case .ticket: return "门票"
        case .hotel: return "酒店"
        }
    }

    var icon: String {
        switch self {
        case .flight: return "airplane"
        case .ticket: return "ticket.fill"
        case .hotel: return "bed.double.fill"
        }
    }
}

@Model
final class TripTicket {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var code: String
    var price: Int
    var statusText: String

    init(kind: TripTicketKind, title: String, code: String = "", price: Int = 0, statusText: String = "待出票") {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.code = code
        self.price = price
        self.statusText = statusText
    }

    var kind: TripTicketKind { TripTicketKind(rawValue: kindRaw) ?? .ticket }
}

// MARK: - 早报条目（SwiftData）
// 内容一律用占位「待生成」，不编造新闻；格式按用户定版：
// 标题「M月D日早报 · 昨日M月D日要闻」，国内 / 国际 / 财经 / 科技四节、连续编号，
// 每项 = 编号 + 加粗关键词 + 一句话 + 来源，10–14 项。

enum BriefingSection: String, Codable, CaseIterable {
    case domestic, international, finance, tech

    var title: String {
        switch self {
        case .domestic: return "国内"
        case .international: return "国际"
        case .finance: return "财经"
        case .tech: return "科技"
        }
    }
}

@Model
final class BriefingItem {
    @Attribute(.unique) var id: UUID
    var sectionRaw: String
    var keyword: String
    var summary: String
    var source: String
    var order: Int

    init(section: BriefingSection, keyword: String, summary: String, source: String, order: Int) {
        self.id = UUID()
        self.sectionRaw = section.rawValue
        self.keyword = keyword
        self.summary = summary
        self.source = source
        self.order = order
    }

    var section: BriefingSection { BriefingSection(rawValue: sectionRaw) ?? .domestic }
}
