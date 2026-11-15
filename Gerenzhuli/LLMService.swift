import Foundation
import Security

// MARK: - 大模型解析服务（占位接口 + 本地规则兜底）
// 流程：语音转写文本 → 本服务解析意图 → 确认卡 → 用户确认后才写入 SwiftData。
// API Key 由用户在设置页自行填写，存在本机钥匙串里，绝不写死在代码里。
// 未配 Key 时用本地规则解析（正则识别相对日期 / 周几 / 几点），解析来源会如实标在确认卡上，
// 绝不冒充大模型。

enum ParsedKind: String, Codable, CaseIterable {
    case reminder, event, subscription, note

    var title: String {
        switch self {
        case .reminder: return "新建提醒"
        case .event: return "新建日程"
        case .subscription: return "新建订阅"
        case .note: return "记一笔"
        }
    }

    var destination: String {
        switch self {
        case .reminder: return "提醒事项"
        case .event: return "日历"
        case .subscription: return "订阅"
        case .note: return "提醒事项"
        }
    }
}

struct ParsedIntent: Codable, Equatable {
    var kind: ParsedKind
    var title: String
    var detail: String
    var date: Date?
    var platform: Platform?
    var priceMonthly: Int?
    /// 解析来源：大模型 / 本地规则（未配 Key）
    var source: String

    init(kind: ParsedKind, title: String, detail: String = "", date: Date? = nil,
         platform: Platform? = nil, priceMonthly: Int? = nil, source: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.date = date
        self.platform = platform
        self.priceMonthly = priceMonthly
        self.source = source
    }
}

// MARK: - 钥匙串（只存 API Key，不存任何用户数据）

enum KeychainHelper {
    private static let service = "com.lidawang.gerenzhuli.llm"
    private static let account = "apiKey"

    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    static func saveAPIKey(_ key: String) {
        deleteAPIKey()
        guard let data = key.data(using: .utf8) else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 大模型服务

@Observable
final class LLMService {
    /// OpenAI 兼容的 chat/completions 接口。用户可在设置页改成自己的网关地址和模型。
    /// 默认端点与模型只是占位，未配 Key 时不会发起任何请求。
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "gzLLMBaseURL") ?? Self.defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: "gzLLMBaseURL") }
    }

    var model: String {
        get { UserDefaults.standard.string(forKey: "gzLLMModel") ?? Self.defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: "gzLLMModel") }
    }

    var hasAPIKey: Bool { KeychainHelper.loadAPIKey() != nil }

    // MARK: 解析入口

    func parse(_ transcript: String) async -> ParsedIntent {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ParsedIntent(kind: .note, title: "", detail: text, source: "本地规则（未配 Key）")
        }
        if let key = KeychainHelper.loadAPIKey(), !key.isEmpty {
            do {
                return try await parseWithLLM(text, apiKey: key)
            } catch {
                // 大模型失败时回落到本地规则，并在来源里如实说明，不静默失败。
                var fallback = LocalIntentParser.parse(text)
                fallback.source = "本地规则（大模型失败：\(error.localizedDescription)）"
                return fallback
            }
        }
        return LocalIntentParser.parse(text)
    }

    // MARK: 大模型（OpenAI 兼容 chat/completions，JSON 输出）

    private struct ChatRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let response_format: ResponseFormat
        struct ResponseFormat: Encodable { let type = "json_object" }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct LLMIntentJSON: Decodable {
        let kind: String
        let title: String
        let detail: String?
        let dateISO: String?
        let platform: String?
        let priceMonthly: Int?
    }

    private func parseWithLLM(_ text: String, apiKey: String) async throws -> ParsedIntent {
        let system = """
        你是个人助理 App 的意图解析器。把用户的一句中文语音转写解析成 JSON，只输出 JSON，不要解释。
        字段：kind（reminder 新建提醒 / event 新建日程 / subscription 新建订阅 / note 记一笔）、
        title（不超过 20 字，去掉“提醒我”“帮我记一下”这类口头语）、detail（一句话说明，可空）、
        dateISO（ISO 8601 日期时间，如 2026-11-16T15:00:00+08:00；没有明确时间就留空）、
        platform（只有 kind 是 subscription 时填：netflix / hbo / disney，否则留空）、
        priceMonthly（只有 kind 是 subscription 且用户说了价格时填每月价格的整数元，否则留空）。
        判断规则：含“提醒/记得/别忘了/到期/续费”→ reminder；含“约/见面/会议/拍摄/日程/排”→ event；
        含“订阅/奈飞/Netflix/HBO/迪士尼/续费某人”→ subscription；其余 → note。
        今天是 \(Date().gzString("yyyy年M月d日 EEEE"))，相对日期（明天/后天/下周）按今天换算。
        """
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        guard let url = URL(string: base + "/chat/completions") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: text),
            ],
            response_format: .init()
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        let intent = try JSONDecoder().decode(LLMIntentJSON.self, from: jsonData)
        let kind = ParsedKind(rawValue: intent.kind) ?? .note
        let date = intent.dateISO.flatMap { ISO8601DateFormatter().date(from: $0) }
        let platform = intent.platform.flatMap { Platform(rawValue: $0) }
        return ParsedIntent(
            kind: kind,
            title: intent.title,
            detail: intent.detail ?? "",
            date: date,
            platform: platform,
            priceMonthly: intent.priceMonthly,
            source: "大模型（\(model)）"
        )
    }
}

// MARK: - 本地规则兜底（未配 Key / 大模型失败时用，来源如实标注）

enum LocalIntentParser {
    static func parse(_ text: String) -> ParsedIntent {
        let lower = text
        let date = extractDate(from: text)
        if lower.contains("订阅") || lower.contains("奈飞") || lower.contains("Netflix")
            || lower.contains("HBO") || lower.contains("迪士尼") || lower.contains("Disney") {
            let platform: Platform? =
                lower.contains("迪士尼") || lower.contains("Disney") ? .disney
                : lower.contains("HBO") ? .hbo
                : (lower.contains("奈飞") || lower.contains("Netflix")) ? .netflix : nil
            let price = extractPrice(from: text)
            return ParsedIntent(
                kind: .subscription,
                title: cleanTitle(text, removing: ["订阅", "奈飞", "Netflix", "HBO", "迪士尼", "Disney"]),
                detail: text,
                date: date,
                platform: platform,
                priceMonthly: price,
                source: "本地规则（未配 Key）"
            )
        }
        if lower.contains("提醒") || lower.contains("记得") || lower.contains("别忘")
            || lower.contains("到期") || lower.contains("续费") {
            return ParsedIntent(
                kind: .reminder,
                title: cleanTitle(text, removing: ["提醒我", "提醒", "记得", "别忘了", "别忘"]),
                detail: text,
                date: date,
                source: "本地规则（未配 Key）"
            )
        }
        if lower.contains("约") || lower.contains("见面") || lower.contains("会议")
            || lower.contains("拍摄") || lower.contains("日程") {
            return ParsedIntent(
                kind: .event,
                title: cleanTitle(text, removing: ["约", "见面", "会议", "拍摄", "日程"]),
                detail: text,
                date: date,
                source: "本地规则（未配 Key）"
            )
        }
        return ParsedIntent(
            kind: .note,
            title: String(text.prefix(20)),
            detail: text,
            date: date,
            source: "本地规则（未配 Key）"
        )
    }

    private static func cleanTitle(_ text: String, removing words: [String]) -> String {
        var title = text
        for word in words { title = title.replacingOccurrences(of: word, with: "") }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，。、："))
        return title.isEmpty ? text : String(title.prefix(20))
    }

    /// 相对日期 + 几点：明天 / 后天 / 大后天 / 下周一…周日，早上 / 下午 / 晚上 / 点 / 半。
    static func extractDate(from text: String) -> Date? {
        let cal = Calendar.current
        let now = Date()
        var dayOffset = 0
        if text.contains("大后天") { dayOffset = 3 }
        else if text.contains("后天") { dayOffset = 2 }
        else if text.contains("明天") { dayOffset = 1 }
        else if text.contains("今天") { dayOffset = 0 }
        else {
            // 下周 X：按下周的那个周几算
            let weekdays = ["周一": 2, "星期一": 2, "周二": 3, "星期二": 3, "周三": 4, "星期三": 4,
                            "周四": 5, "星期四": 5, "周五": 6, "星期五": 6, "周六": 7, "星期六": 7,
                            "周日": 1, "星期日": 1, "周天": 1, "星期天": 1]
            for (label, weekday) in weekdays where text.contains(label) {
                var target = cal.nextDate(after: now, matching: DateComponents(weekday: weekday),
                                          matchingPolicy: .nextTimePreservingSmallerComponents) ?? now
                if text.contains("下周") || text.contains("下星期") {
                    target = cal.date(byAdding: .day, value: 7, to: target) ?? target
                }
                dayOffset = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                               to: cal.startOfDay(for: target)).day ?? 0
                break
            }
        }
        var hour = 9, minute = 0
        var hasTime = false
        // “下午三点半 / 15点 / 晚上8点”：先找数字 + 点
        let pattern = #"([上下]午|中午|晚上|早上|凌晨)?\s*(\d{1,2})\s*点\s*(半)?"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            let slice = String(text[match])
            let digits = slice.filter { $0.isNumber }
            if let h = Int(digits) {
                hasTime = true
                hour = h
                if slice.contains("下午") || slice.contains("中午") || slice.contains("晚上") {
                    if hour < 12 { hour += 12 }
                }
                if slice.contains("半") { minute = 30 }
            }
        }
        // 中文数字时间：“下午三点 / 十一点半 / 十二点”——以前只认阿拉伯数字，
        // “三点”匹配不上就回落到默认 09:00，示例句“明天下午三点”会被错解析成 09:00。
        if !hasTime,
           let regex = try? NSRegularExpression(pattern: #"([上下]午|中午|晚上|早上|凌晨)?\s*([一二三四五六七八九十]+)\s*点\s*(半)?"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.range(at: 2).location != NSNotFound,
           let numeralRange = Range(match.range(at: 2), in: text),
           let h = chineseHour(String(text[numeralRange])) {
            hasTime = true
            hour = h
            if let periodRange = Range(match.range(at: 1), in: text) {
                let period = String(text[periodRange])
                if (period == "下午" || period == "中午" || period == "晚上") && hour < 12 { hour += 12 }
            }
            if match.range(at: 3).location != NSNotFound { minute = 30 }
        }
        guard dayOffset != 0 || hasTime else { return nil }
        let day = cal.date(byAdding: .day, value: dayOffset, to: now) ?? now
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// 中文数字转小时：“三”→3，“十”→10，“十一”→11，“十二”→12，“二十一”→21。
    private static func chineseHour(_ s: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if s.count == 1, let v = digits[s.first!] { return v }
        guard let tenIndex = s.firstIndex(of: "十") else { return nil }
        let before = String(s[..<tenIndex])
        let after = String(s[s.index(after: tenIndex)...])
        let tens = before.isEmpty ? 1 : digits[before.first ?? " "] ?? 0
        let ones = after.isEmpty ? 0 : digits[after.first ?? " "] ?? 0
        return tens * 10 + ones
    }

    /// “20元 / 20块一个月” → 每月价格（整数元）
    private static func extractPrice(from text: String) -> Int? {
        let pattern = #"(\d+)\s*(元|块)"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = String(text[match]).filter { $0.isNumber }
        return Int(digits)
    }
}
