import AVFoundation
import EventKit
import Foundation
import Speech
import SwiftUI

// MARK: - 系统权限（提醒事项 + 日历走 EventKit，语音走麦克风 + 语音识别）
// 首次打开由用户逐项点允许；数据只留在本机。权限被拒时界面给降级提示，不静默失败。
// TODO(真实数据): 授权通过后，用 EKEventStore 拉取本机提醒/日历，
// 替换 Store.swift 里的种子；未授权时继续用本机种子，不阻塞使用。

@Observable
final class PermissionsService {
    enum Status {
        case notDetermined, authorized, denied, restricted

        var title: String {
            switch self {
            case .notDetermined: return "去允许"
            case .authorized: return "已允许"
            case .denied: return "去设置"
            case .restricted: return "受限"
            }
        }

        var isAuthorized: Bool { self == .authorized }
    }

    var reminderStatus: Status = .notDetermined
    var calendarStatus: Status = .notDetermined
    var microphoneStatus: Status = .notDetermined
    var speechStatus: Status = .notDetermined

    private let eventStore = EKEventStore()

    init() {
        refreshFromSystem()
    }

    /// 以系统当前授权状态刷新（不弹窗）。
    func refreshFromSystem() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .authorized, .fullAccess: reminderStatus = .authorized
        case .denied: reminderStatus = .denied
        case .restricted: reminderStatus = .restricted
        case .notDetermined: reminderStatus = .notDetermined
        @unknown default: reminderStatus = .notDetermined
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess: calendarStatus = .authorized
        case .denied: calendarStatus = .denied
        case .restricted: calendarStatus = .restricted
        case .notDetermined: calendarStatus = .notDetermined
        @unknown default: calendarStatus = .notDetermined
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: microphoneStatus = .authorized
        case .denied: microphoneStatus = .denied
        case .undetermined: microphoneStatus = .notDetermined
        @unknown default: microphoneStatus = .notDetermined
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechStatus = .authorized
        case .denied: speechStatus = .denied
        case .restricted: speechStatus = .restricted
        case .notDetermined: speechStatus = .notDetermined
        @unknown default: speechStatus = .notDetermined
        }
    }

    @MainActor
    func requestReminders() async {
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToReminders()
                reminderStatus = granted ? .authorized : .denied
            } catch {
                reminderStatus = .denied
            }
        } else {
            eventStore.requestAccess(to: .reminder) { [weak self] granted, _ in
                Task { @MainActor in self?.reminderStatus = granted ? .authorized : .denied }
            }
        }
    }

    @MainActor
    func requestCalendar() async {
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                calendarStatus = granted ? .authorized : .denied
            } catch {
                calendarStatus = .denied
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                Task { @MainActor in self?.calendarStatus = granted ? .authorized : .denied }
            }
        }
    }

    @MainActor
    func requestMicrophone() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        microphoneStatus = granted ? .authorized : .denied
    }

    @MainActor
    func requestSpeech() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        switch status {
        case .authorized: speechStatus = .authorized
        case .denied: speechStatus = .denied
        case .restricted: speechStatus = .restricted
        case .notDetermined: speechStatus = .notDetermined
        @unknown default: speechStatus = .notDetermined
        }
    }

    /// 被拒后去系统设置里打开。
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 语音输入权限（麦克风 + 语音识别）

    /// 语音输入开始前调用；两项都通过才返回 true。被拒时调用方给出去设置的入口。
    @MainActor
    func requestVoice() async -> Bool {
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
        speechStatus = speechGranted ? .authorized : .denied
        microphoneStatus = micGranted ? .authorized : .denied
        return speechGranted && micGranted
    }

    /// 麦克风当前状态：用于设置页展示。
    var microphoneAuthorized: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    /// 语音识别当前状态：用于设置页展示。
    var speechAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
}
