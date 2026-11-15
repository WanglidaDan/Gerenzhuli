import AVFoundation
import Foundation
import Speech
import SwiftUI

// MARK: - 语音输入：Speech 框架转文字 + 实时音量（波形用）
// 打开 App 点麦克风直接说；转写是实时的，说完点完成就拿去解析。
// 麦克风 + 语音识别两项权限在开始录音前申请，被拒时给出去设置的入口，不静默失败。

@Observable
final class VoiceInputService {
    enum AuthState {
        case notDetermined, authorized, denied

        var title: String {
            switch self {
            case .notDetermined: return "未申请"
            case .authorized: return "已允许"
            case .denied: return "被拒绝"
            }
        }
    }

    var isRecording = false
    var transcript = ""
    var isFinal = false
    /// 0…1，实时音量，聆听面板的波形条用它驱动。
    var audioLevel: CGFloat = 0
    var authState: AuthState = .notDetermined
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var levelTimer: Timer?

    init() {
        refreshAuthState()
    }

    func refreshAuthState() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioSession.sharedInstance().recordPermission
        switch (speechStatus, micStatus) {
        case (.authorized, .granted):
            authState = .authorized
        case (.denied, _), (_, .denied):
            authState = .denied
        default:
            authState = .notDetermined
        }
    }

    /// 麦克风 + 语音识别两项一起申请。
    @MainActor
    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        refreshAuthState()
        let granted = speechGranted && micGranted
        if !granted {
            errorMessage = "麦克风或语音识别没允许，去设置里打开后才能语音输入。"
        }
        return granted
    }

    @MainActor
    func start() async -> Bool {
        guard recognizer?.isAvailable == true else {
            errorMessage = "语音识别现在不可用，检查网络后重试。"
            return false
        }
        if authState != .authorized {
            guard await requestAuthorization() else { return false }
        }
        errorMessage = nil
        transcript = ""
        isFinal = false
        audioLevel = 0

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "打不开麦克风：\(error.localizedDescription)"
            return false
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 设备端识别（iOS 17+ 支持中文设备端识别，联网失败时仍可用）
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateLevel(from: buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "录音启动失败：\(error.localizedDescription)"
            return false
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.isFinal = result.isFinal
                }
                if error != nil || result?.isFinal == true {
                    self.stopEngine()
                }
            }
        }
        isRecording = true
        startLevelDecay()
        return true
    }

    /// 停止录音并返回最终转写文本。
    @MainActor
    func stop() -> String {
        stopEngine()
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    func cancel() {
        stopEngine()
        transcript = ""
        isFinal = false
        audioLevel = 0
    }

    private func stopEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        levelTimer?.invalidate()
        levelTimer = nil
        isRecording = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 实时音量：取 buffer 的 RMS，归一化到 0…1。
    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for i in 0..<count {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        // 人声 RMS 通常在 0.01…0.5 之间，映射到 0…1
        let level = CGFloat(min(max((rms - 0.01) / 0.3, 0), 1))
        Task { @MainActor in
            // 平滑一下，波形不抖
            self.audioLevel = self.audioLevel * 0.6 + level * 0.4
        }
    }

    /// 无声时音量慢慢回落，波形不卡在高位。
    private func startLevelDecay() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.audioLevel > 0.02 {
                    self.audioLevel *= 0.75
                }
            }
        }
    }
}
