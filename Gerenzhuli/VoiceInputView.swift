import SwiftData
import SwiftUI

// MARK: - 语音输入：聆听面板 + 解析确认卡
// 打开 App 点麦克风直接说 → Speech 实时转写 → 大模型（或本地规则）解析意图 →
// 确认卡（类型、标题、时间、去向都可改）→ 用户点确认才写入 SwiftData。

enum VoicePhase {
    case listening, parsing, confirming(ParsedIntent), failed(String)
}

struct VoiceInputView: View {
    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var service = VoiceInputService()
    @State private var llm = LLMService()
    @State private var phase: VoicePhase = .listening
    @State private var started = false
    /// 声波呼吸：聆听时缓慢缩放，区别于音量驱动的波形跳动
    @State private var breathing = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .listening:
                    listeningBody
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .parsing:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在分析你说的话…")
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                        if !service.transcript.isEmpty {
                            Text("“\(service.transcript)”")
                                .font(.gzBody)
                                .foregroundStyle(Color.gzText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                case .confirming(let intent):
                    VoiceConfirmView(intent: intent) {
                        dismiss()
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.gzAmber)
                        Text(message)
                            .font(.gzBody)
                            .foregroundStyle(Color.gzText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("再说一次") {
                            withAnimation(GZ.spring) { phase = .listening }
                            Task { await startListening() }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.gzInkGreen2)
                        .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.gzBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        Task { @MainActor in service.cancel() }
                        dismiss()
                    }
                }
            }
            .task {
                if !started {
                    started = true
                    await startListening()
                }
            }
            .onDisappear {
                Task { @MainActor in service.cancel() }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: 聆听面板

    private var listeningBody: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            Text(service.isRecording ? "正在听…" : "准备聆听…")
                .font(.gzTitle)
                .foregroundStyle(Color.gzText)
            WaveformView(level: service.audioLevel, isActive: service.isRecording)
                .frame(height: 56)
                .padding(.horizontal, 32)
                .scaleEffect(breathing && service.isRecording ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: breathing)
                .onAppear { breathing = true }
            Text(service.transcript.isEmpty ? "说一句话，比如：明天下午三点提醒我给 k 续费" : service.transcript)
                .font(.gzBody)
                .foregroundStyle(service.transcript.isEmpty ? Color.gzSecondary : Color.gzText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .frame(minHeight: 60)
            if let error = service.errorMessage {
                Text(error)
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Button {
                Task { await finishListening() }
            } label: {
                Text("完成，说完了")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.gzInkGreen2)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .gzPressable()
            .padding(.horizontal, 20)
            Button("去设置打开麦克风权限") {
                PermissionsService().openSettings()
            }
            .font(.gzFootnote)
            .foregroundStyle(Color.gzSecondary)
            .opacity(service.authState == .denied ? 1 : 0)
            Spacer(minLength: 8)
        }
    }

    private func startListening() async {
        let ok = await service.start()
        if !ok && service.authState == .denied {
            withAnimation(GZ.spring) { phase = .failed("麦克风或语音识别没允许，去设置里打开后才能语音输入。") }
        }
    }

    private func finishListening() async {
        let text = await service.stop()
        guard !text.isEmpty else {
            withAnimation(GZ.spring) { phase = .failed("没听到你说什么，再说一次吧。") }
            return
        }
        withAnimation(GZ.spring) { phase = .parsing }
        let intent = await llm.parse(text)
        withAnimation(GZ.spring) { phase = .confirming(intent) }
    }
}

// MARK: - 波形条：音量驱动，每帧用 TimelineView 重绘

struct WaveformView: View {
    let level: CGFloat
    let isActive: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<28, id: \.self) { i in
                    let wave = isActive
                        ? 0.25 + 0.75 * abs(sin(t * 5 + Double(i) * 0.55))
                        : 0.25
                    let height = 8 + CGFloat(wave) * level * 44 + (isActive ? 0 : 0)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.gzInkGreen2)
                        .frame(width: 3, height: max(6, height))
                        .animation(.none, value: t)
                }
            }
        }
    }
}

// MARK: - 解析确认卡：类型、标题、时间、去向都可改，确认才写入

struct VoiceConfirmView: View {
    let intent: ParsedIntent
    var onDone: () -> Void

    @Environment(Store.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ParsedKind
    @State private var title: String
    @State private var detail: String
    @State private var hasDate: Bool
    @State private var date: Date
    /// 订阅平台：解析没提到平台时保持 nil，确认卡必须让用户选，不再默认 Netflix。
    @State private var platform: Platform?
    @State private var priceText: String
    @State private var saved = false
    /// 保存失败时的报错（不显示“已添加”冒充成功）。
    @State private var saveError: String?
    /// 确认卡入场：弹簧缩放弹出（只走 transform / opacity）
    @State private var popped = false

    init(intent: ParsedIntent, onDone: @escaping () -> Void) {
        self.intent = intent
        self.onDone = onDone
        // 无明确时间的日程：默认明天 09:00，而不是点确认那一刻（否则首页
        // `date >= now` 会立刻把它滤掉，看起来像刚保存就消失）。
        let defaultDate: Date = {
            if let d = intent.date { return d }
            if intent.kind == .event {
                let cal = Calendar.current
                let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            }
            return Date()
        }()
        _kind = State(initialValue: intent.kind)
        _title = State(initialValue: intent.title)
        _detail = State(initialValue: intent.detail)
        _hasDate = State(initialValue: intent.date != nil || intent.kind == .event)
        _date = State(initialValue: defaultDate)
        _platform = State(initialValue: intent.platform)
        _priceText = State(initialValue: intent.priceMonthly.map { "\($0)" } ?? "")
    }

    /// 无明确时间的日程默认时间：明天 09:00。
    private func tomorrowAtNine() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("听到了这样一件事")
                        .font(.gzTitle)
                        .foregroundStyle(Color.gzText)
                    Text("确认无误再添加，不对可以直接改。")
                        .font(.gzFootnote)
                        .foregroundStyle(Color.gzSecondary)
                }

                // 类型
                VStack(alignment: .leading, spacing: 8) {
                    GZSectionHeader(title: "类型")
                    Picker("", selection: $kind) {
                        ForEach(ParsedKind.allCases, id: \.self) { k in
                            Text(k.title).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 内容卡
                VStack(spacing: 0) {
                    TextField("标题", text: $title)
                        .font(.gzHeadline)
                    Divider()
                    TextField("一句话说明（可选）", text: $detail)
                        .font(.gzBody)
                    Divider()
                    HStack {
                        Text("去向")
                            .font(.gzBody)
                            .foregroundStyle(Color.gzSecondary)
                        Spacer()
                        Text(kind.destination)
                            .font(.gzHeadline)
                            .foregroundStyle(Color.gzText)
                    }
                    Divider()
                    Toggle("带时间", isOn: $hasDate)
                        .font(.gzBody)
                    if hasDate {
                        Divider()
                        DatePicker("时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .font(.gzBody)
                    }
                    if kind == .subscription {
                        Divider()
                        Picker("平台", selection: $platform) {
                            Text("请选择").tag(nil as Platform?)
                            ForEach(Platform.allCases, id: \.self) { p in
                                Text(p.title).tag(Optional(p))
                            }
                        }
                        .font(.gzBody)
                        if platform == nil {
                            Text("请选择平台才能添加，不要默认成 Netflix。")
                                .font(.gzFootnote)
                                .foregroundStyle(Color.gzRed)
                        }
                        Divider()
                        HStack {
                            Text("每月价格")
                                .font(.gzBody)
                                .foregroundStyle(Color.gzSecondary)
                            Spacer()
                            TextField("元/月", text: $priceText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.gzHeadline)
                                .frame(width: 90)
                            Text("元/月")
                                .font(.gzFootnote)
                                .foregroundStyle(Color.gzSecondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .gzCardStyle()

                // 解析来源：如实标注，不冒充大模型
                Text("解析来源：\(intent.source)")
                    .font(.gzCaption)
                    .foregroundStyle(Color.gzTertiary)

                if let saveError {
                    Text(saveError)
                        .font(.gzFootnote)
                        .foregroundStyle(Color.gzRed)
                }

                Button {
                    save()
                } label: {
                    Text(saved ? "已添加" : "确认添加")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.gzInkGreen2)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .gzPressable()
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saved
                          || (kind == .subscription && platform == nil))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scaleEffect(popped ? 1 : 0.96)
        .opacity(popped ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { popped = true }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        // 无明确时间：日程默认明天 09:00（不是点确认那一刻，否则首页立刻滤掉）；
        // 提醒 / 记一笔仍用此刻。
        let when = hasDate ? date : (kind == .event ? tomorrowAtNine() : Date())
        var ok = false
        switch kind {
        case .reminder, .note:
            ok = store.addReminder(title: cleanTitle, detail: detail, date: when, in: modelContext)
        case .event:
            ok = store.addEvent(title: cleanTitle, note: detail, date: when, in: modelContext)
        case .subscription:
            guard let platform else {
                saveError = "请先选择平台。"
                return
            }
            let price = Int(priceText.filter { $0.isNumber }) ?? 0
            // 订阅的“时间”是指到期日；没说时间时默认一个月后到期，不写今天（否则一建好就显示已过期）。
            let expiry = hasDate ? date : (Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            ok = store.addSubscriber(
                name: cleanTitle,
                profile: "待确认",
                platform: platform,
                priceMonthly: price,
                billingLabel: price > 0 ? "\(price)元/月" : "价格待定",
                expiry: expiry,
                note: detail,
                in: modelContext
            )
        }
        // 保存失败不要显示“已添加”，如实报错。
        guard ok else {
            saveError = "保存失败，请再试一次。"
            return
        }
        saved = true
        dismiss()
        onDone()
    }
}
