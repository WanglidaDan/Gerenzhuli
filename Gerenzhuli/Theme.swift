import SwiftUI

// MARK: - 个人助理 · 设计语言（定稿精修版）
// 系统字体 SF Pro，字号按 SwiftUI 字阶往下收；分组列表质感，少文案、留白大。

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    private static func adaptive(dark: UInt, light: UInt, darkAlpha: Double = 1.0, lightAlpha: Double = 1.0) -> Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: dark, alpha: darkAlpha)
            } else {
                return UIColor(hex: light, alpha: lightAlpha)
            }
        })
    }

    // 深色纯黑底 + #1C1C1E 系统色；浅色用系统分组灰
    static let gzBackground = adaptive(dark: 0x000000, light: 0xF2F2F7)
    static let gzCard       = adaptive(dark: 0x1C1C1E, light: 0xFFFFFF)
    static let gzCard2      = adaptive(dark: 0x2C2C2E, light: 0xE9E9EE)
    static let gzText       = adaptive(dark: 0xFFFFFF, light: 0x1A1A1E)
    static let gzSecondary  = adaptive(dark: 0x98989D, light: 0x6E6E74)
    static let gzTertiary   = adaptive(dark: 0x48484A, light: 0xC9C9CF)
    // 0.5px 发丝线：用极低透明度的描边实现
    static let gzHairline   = adaptive(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.09, lightAlpha: 0.08)
    static let gzShadow     = adaptive(dark: 0x000000, light: 0x1A1A1E, darkAlpha: 0.0, lightAlpha: 0.07)
    static let gzGreen      = Color(hex: 0x30D158)
    static let gzRed        = Color(hex: 0xFF453A)
    static let gzAmber      = Color(hex: 0xFF9F0A)
    static let gzBlue       = Color(hex: 0x0A84FF)
    static let gzInkGreen   = Color(hex: 0x0F3D2E)
    static let gzInkGreen2  = Color(hex: 0x1A5C46)
}

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

// MARK: - 字阶：大标题 25，正文 12.5–14，数字等宽

extension Font {
    static let gzLargeTitle = Font.system(size: 25, weight: .semibold)
    static let gzTitle      = Font.system(size: 17, weight: .semibold)
    static let gzHeadline   = Font.system(size: 14, weight: .semibold)
    static let gzBody       = Font.system(size: 13.5, weight: .regular)
    static let gzSubhead    = Font.system(size: 13, weight: .medium)
    static let gzFootnote   = Font.system(size: 12.5, weight: .regular)
    static let gzCaption    = Font.system(size: 11.5, weight: .regular)
    static let gzNumber     = Font.system(size: 14, weight: .semibold).monospacedDigit()
    static let gzNumberLarge = Font.system(size: 25, weight: .semibold).monospacedDigit()
}

enum GZ {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let springSoft = Animation.spring(response: 0.5, dampingFraction: 0.85)
    /// 按压缩放：0.97（配合轻震，不花哨）
    static let pressScale: CGFloat = 0.97

    /// 早报卡：深墨绿细腻渐变
    static let briefingGradient = LinearGradient(
        colors: [Color(hex: 0x0F3D2E), Color(hex: 0x1A5C46)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 按压 0.97 回弹 + 轻震（真机能感到，iOS 17+）
struct GZPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? GZ.pressScale : 1.0)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 入场：淡入 + 轻微上浮，可带 stagger 延迟；只走 transform / opacity
private struct GZAppearModifier: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(GZ.springSoft.delay(delay)) { shown = true }
            }
    }
}

/// 列表行插入 / 移除：缩放 + 淡出（滑出屏幕时同款过渡）
private struct GZListTransitionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.transition(.asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .scale(scale: 0.94).combined(with: .opacity)
        ))
    }
}

extension View {
    func gzPressable() -> some View { buttonStyle(GZPressableStyle()) }

    /// 入场淡入 + 上浮（delay 做 stagger）
    func gzAppear(delay: Double = 0) -> some View {
        modifier(GZAppearModifier(delay: delay))
    }

    /// 列表行插入 / 移除过渡
    func gzListTransition() -> some View {
        modifier(GZListTransitionModifier())
    }

    /// 滚动时滑出屏幕的卡片：缩放 + 淡出（只走 transform / opacity）
    func gzScrollFade() -> some View {
        self.scrollTransition { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                .opacity(phase.isIdentity ? 1 : 0.55)
        }
    }

    /// 分组列表卡片：圆角 12–14 + 0.5px 发丝线 + 柔和层叠阴影
    func gzCardStyle(cornerRadius: CGFloat = 13) -> some View {
        self
            .background(Color.gzCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.gzHairline, lineWidth: 0.5)
            )
            .shadow(color: Color.gzShadow, radius: 8, y: 2)
    }

    /// 发丝线分隔
    func gzHairline() -> some View {
        Rectangle().fill(Color.gzHairline).frame(height: 0.5)
    }
}

extension Double {
    /// ¥926 / ¥18,800（不带小数）
    var cny: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return "¥" + (f.string(from: NSNumber(value: self)) ?? "\(Int(self))")
    }
}

extension Int {
    var cny: String { Double(self).cny }
}

extension Date {
    func gzString(_ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f.string(from: self)
    }

    /// “11月15日” / “11月14日”
    var gzMonthDay: String { gzString("M月d日") }
}

/// 按时间问候：早上好 / 下午好 / 晚上好
func greetingForNow(_ date: Date = Date()) -> String {
    let hour = Calendar.current.component(.hour, from: date)
    switch hour {
    case 5..<12: return "早上好"
    case 12..<18: return "下午好"
    default: return "晚上好"
    }
}
