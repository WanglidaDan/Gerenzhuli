import SwiftUI

// MARK: - 首次打开：四项权限分开申请
// 文案只说用途与“数据只留在本机”，不写技术名词。

struct OnboardingView: View {
    @AppStorage("gzOnboardingDone") private var onboardingDone = false
    @Environment(PermissionsService.self) private var permissions
    @State private var showDeniedAlert = false
    @State private var deniedTitle = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("个人助理")
                            .font(.gzLargeTitle)
                            .foregroundStyle(Color.gzText)
                        Text("只为你一个人服务。")
                            .font(.gzBody)
                            .foregroundStyle(Color.gzSecondary)
                        Text("先允许下面四项，才能帮你管日程、提醒，还能语音记事。数据只留在本机。")
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                            .padding(.top, 2)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        permissionRow(
                            icon: "checklist",
                            title: "提醒事项",
                            detail: "查看、勾选和新建你的待办。",
                            status: permissions.reminderStatus,
                            action: { Task { await permissions.requestReminders(); checkDenied(permissions.reminderStatus, title: "提醒事项") } }
                        )
                        Divider().padding(.leading, 52)
                        permissionRow(
                            icon: "calendar",
                            title: "日历",
                            detail: "读取当天的日程，帮你排好接下来要做的事。",
                            status: permissions.calendarStatus,
                            action: { Task { await permissions.requestCalendar(); checkDenied(permissions.calendarStatus, title: "日历") } }
                        )
                        Divider().padding(.leading, 52)
                        permissionRow(
                            icon: "mic.fill",
                            title: "麦克风",
                            detail: "语音输入时收音，说完自动转成文字。",
                            status: permissions.microphoneStatus,
                            action: { Task { await permissions.requestMicrophone(); checkDenied(permissions.microphoneStatus, title: "麦克风") } }
                        )
                        Divider().padding(.leading, 52)
                        permissionRow(
                            icon: "waveform",
                            title: "语音识别",
                            detail: "把说的话转成文字，再由大模型解析。",
                            status: permissions.speechStatus,
                            action: { Task { await permissions.requestSpeech(); checkDenied(permissions.speechStatus, title: "语音识别") } }
                        )
                    }
                    .gzCardStyle()
                    .padding(.top, 4)

                    // 降级提示：被拒也不阻塞使用
                    if permissions.reminderStatus == .denied
                        || permissions.calendarStatus == .denied
                        || permissions.microphoneStatus == .denied
                        || permissions.speechStatus == .denied {
                        Text("有一项没允许也没关系，先用着，随时可以在设置里打开。")
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                    }

                    Spacer(minLength: 24)

                    Button {
                        onboardingDone = true
                    } label: {
                        Text("开始使用")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.gzInkGreen2)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .gzPressable()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color.gzBackground)
            .navigationBarTitleDisplayMode(.inline)
            .alert("没有拿到\(deniedTitle)权限", isPresented: $showDeniedAlert) {
                Button("去设置", role: .none) { permissions.openSettings() }
                Button("先不用", role: .cancel) {}
            } message: {
                Text("可以在系统设置里打开，打开后日程和提醒会自动同步。")
            }
        }
    }

    private func checkDenied(_ status: PermissionsService.Status, title: String) {
        if status == .denied {
            deniedTitle = title
            showDeniedAlert = true
        }
    }

    private func permissionRow(icon: String, title: String, detail: String, status: PermissionsService.Status, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.gzInkGreen2)
                .frame(width: 36, height: 36)
                .background(Color.gzCard2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gzHeadline)
                    .foregroundStyle(Color.gzText)
                Text(detail)
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: action) {
                Text(status.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(status.isAuthorized ? Color.gzGreen : Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(status.isAuthorized ? Color.gzGreen.opacity(0.12) : Color.gzInkGreen2)
                    .clipShape(Capsule())
            }
            .gzPressable()
            .disabled(status.isAuthorized)
        }
        .padding(14)
    }
}
