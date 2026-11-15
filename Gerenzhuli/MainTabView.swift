import SwiftUI

// MARK: - 主界面：五个页签，底部毛玻璃标签栏
// 切页动效：内容淡入 + 轻微上浮（弹簧），标签栏选中态用 matchedGeometryEffect 滑过去；
// 五个页签常驻在视图树里（只改透明度 / 位移），切页不丢各页滚动位置。

enum GZTab: String, CaseIterable {
    case home, calendar, reminders, subscribers, travel

    var title: String {
        switch self {
        case .home: "今日"
        case .calendar: "日历"
        case .reminders: "提醒"
        case .subscribers: "订阅"
        case .travel: "出行"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .subscribers: "play.tv.fill"
        case .travel: "map"
        }
    }
}

struct MainTabView: View {
    @State private var tab: GZTab = .home
    @State private var showVoice = false
    @Namespace private var tabPill

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    tabPage(.home) { HomeView() }
                    tabPage(.calendar) { CalendarView() }
                    tabPage(.reminders) { RemindersView() }
                    tabPage(.subscribers) { SubscribersView() }
                    tabPage(.travel) { TravelView() }
                }
                .animation(GZ.spring, value: tab)

                tabBar
            }

            // 语音输入常驻入口：点麦克风直接说，大模型解析后确认添加。
            Button { showVoice = true } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.gzInkGreen2)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .gzPressable()
            .padding(.trailing, 20)
            .padding(.bottom, 96)
            .accessibilityLabel("语音输入")
        }
        .sheet(isPresented: $showVoice) {
            VoiceInputView()
        }
    }

    /// 单个页签页：选中时淡入 + 上浮；未选中时透明下沉并禁用点按（仍保留在树里，不丢状态）。
    private func tabPage<T: View>(_ page: GZTab, @ViewBuilder content: () -> T) -> some View {
        content()
            .opacity(tab == page ? 1 : 0)
            .offset(y: tab == page ? 0 : 10)
            .disabled(tab != page)
            .allowsHitTesting(tab == page)
    }

    /// 自定义底部标签栏：选中胶囊用 matchedGeometryEffect 在五个图标下滑过去。
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(GZTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(GZ.spring) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        ZStack {
                            if tab == t {
                                Capsule()
                                    .fill(Color.gzInkGreen2.opacity(0.14))
                                    .matchedGeometryEffect(id: "tabPill", in: tabPill)
                                    .frame(width: 52, height: 30)
                            }
                            Image(systemName: t.icon)
                                .font(.system(size: 19, weight: .semibold))
                        }
                        Text(t.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(tab == t ? Color.gzInkGreen2 : Color.gzSecondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.gzHairline).frame(height: 0.5)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }
}
