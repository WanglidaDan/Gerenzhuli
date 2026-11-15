import SwiftUI

// MARK: - 设置：大模型 API Key（钥匙串）、接口地址、模型、权限状态
// Key 由用户自己填，只存在本机钥匙串，绝不写死在代码里、不进版本控制、不上传。
// 未配 Key 时语音解析走本地规则，确认卡上会如实标注。

struct SettingsView: View {
    @Environment(PermissionsService.self) private var permissions
    @Environment(\.dismiss) private var dismiss

    @State private var llm = LLMService()
    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var keySaved = false
    @State private var showKey = false
    @State private var savedNotice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("语音解析的大模型")
                            .font(.gzHeadline)
                        Text("填好 Key 后，语音说的话由大模型解析；没填时用本地规则解析，确认卡上会写明来源。Key 只存在本机钥匙串。")
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                    }
                    HStack {
                        Text("API Key")
                            .font(.gzBody)
                        Spacer()
                        if showKey {
                            TextField("sk-…", text: $apiKey)
                                .multilineTextAlignment(.trailing)
                                .font(.gzBody)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField(llm.hasAPIKey ? "已保存（点眼睛查看）" : "sk-…", text: $apiKey)
                                .multilineTextAlignment(.trailing)
                                .font(.gzBody)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.gzSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Text("接口地址")
                            .font(.gzBody)
                        Spacer()
                        TextField("https://api.openai.com/v1", text: $baseURL)
                            .multilineTextAlignment(.trailing)
                            .font(.gzBody)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    HStack {
                        Text("模型")
                            .font(.gzBody)
                        Spacer()
                        TextField("gpt-4o-mini", text: $model)
                            .multilineTextAlignment(.trailing)
                            .font(.gzBody)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    HStack(spacing: 10) {
                        Button("保存") { save() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.gzInkGreen2)
                            .clipShape(Capsule())
                        if llm.hasAPIKey || keySaved {
                            Button("清除 Key", role: .destructive) {
                                KeychainHelper.deleteAPIKey()
                                apiKey = ""
                                keySaved = false
                                savedNotice = "Key 已清除，语音解析改走本地规则。"
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }
                        if let savedNotice {
                            Text(savedNotice)
                                .font(.gzCaption)
                                .foregroundStyle(Color.gzSecondary)
                        }
                    }
                } header: {
                    Text("大模型")
                }

                Section {
                    permissionRow(title: "提醒事项", status: permissions.reminderStatus)
                    permissionRow(title: "日历", status: permissions.calendarStatus)
                    HStack {
                        Text("麦克风")
                            .font(.gzBody)
                        Spacer()
                        Text(permissions.microphoneAuthorized ? "已允许" : "未允许")
                            .font(.gzFootnote)
                            .foregroundStyle(permissions.microphoneAuthorized ? Color.gzGreen : Color.gzSecondary)
                    }
                    HStack {
                        Text("语音识别")
                            .font(.gzBody)
                        Spacer()
                        Text(permissions.speechAuthorized ? "已允许" : "未允许")
                            .font(.gzFootnote)
                            .foregroundStyle(permissions.speechAuthorized ? Color.gzGreen : Color.gzSecondary)
                    }
                    Button("打开系统设置") { permissions.openSettings() }
                        .font(.gzBody)
                } header: {
                    Text("权限")
                }

                Section {
                    HStack {
                        Text("版本")
                            .font(.gzBody)
                        Spacer()
                        Text("1.0.0")
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                    }
                    Text("只为你一个人服务，数据只留在本机。")
                        .font(.gzFootnote)
                        .foregroundStyle(Color.gzSecondary)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                baseURL = llm.baseURL
                model = llm.model
                keySaved = llm.hasAPIKey
                if llm.hasAPIKey {
                    // 已保存的 Key 不回显明文，只显示占位，改 Key 时重新输入即可。
                    apiKey = ""
                }
            }
        }
    }

    private func save() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            KeychainHelper.saveAPIKey(key)
            keySaved = true
        }
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty { llm.baseURL = url }
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { llm.model = m }
        savedNotice = keySaved ? "已保存。" : "接口地址和模型已保存（Key 未填，走本地规则）。"
        apiKey = ""
        showKey = false
    }

    private func permissionRow(title: String, status: PermissionsService.Status) -> some View {
        HStack {
            Text(title)
                .font(.gzBody)
            Spacer()
            Text(status.title)
                .font(.gzFootnote)
                .foregroundStyle(status.isAuthorized ? Color.gzGreen : Color.gzSecondary)
        }
    }
}
