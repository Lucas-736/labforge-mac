import Foundation
import UserNotifications

/// Bundle-guarded daily check-in reminder.
///
/// `UNUserNotificationCenter.current()` raises an uncatchable Objective-C exception when the process
/// is not running from a real `.app` bundle (e.g. `swift run` / bare executable), so every access goes
/// through `isAvailable` first.
@MainActor
final class NotificationService {

    enum Status: Equatable {
        case unavailable
        case notDetermined
        case denied
        case authorized(scheduled: Bool)
        case error(String)
    }

    static let reminderIdentifier = "com.labforge.app.daily-reminder"

    /// `true` only inside a real `.app` bundle with a bundle identifier.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var center: UNUserNotificationCenter? {
        Self.isAvailable ? UNUserNotificationCenter.current() : nil
    }

    /// Current authorization + scheduling state.
    func currentStatus() async -> Status {
        guard let center else { return .unavailable }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            let pending = await center.pendingNotificationRequests()
            return .authorized(scheduled: pending.contains { $0.identifier == Self.reminderIdentifier })
        @unknown default:
            return .notDetermined
        }
    }

    /// Requests permission if needed and (re)schedules the daily reminder.
    func scheduleDailyReminder(hour: Int, minute: Int) async -> Status {
        guard let center else { return .unavailable }
        do {
            let settings = await center.notificationSettings()
            try Task.checkCancellation()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if !granted { return .denied }
            } else if settings.authorizationStatus == .denied {
                return .denied
            }

            try Task.checkCancellation()

            let content = UNMutableNotificationContent()
            content.title = "LabForge 研铸 · 打卡提醒"
            content.body = "新的一天，进实验室点一下「进入实验室打卡」，让今天的努力被记录下来。"
            content.sound = .default

            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: Self.reminderIdentifier, content: content, trigger: trigger)
            try await center.add(request)
            return .authorized(scheduled: true)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func cancelDailyReminder() {
        center?.removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }

    /// Chinese explanation for the Settings banner.
    static func description(for status: Status, enabled: Bool, hour: Int, minute: Int) -> String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch status {
        case .unavailable:
            return "当前以裸可执行文件运行（非 .app 包），系统通知不可用。请通过 /Applications/LabForge.app 启动后再开启提醒。"
        case .notDetermined:
            return enabled ? "正在等待通知授权……" : "开启后，LabForge 会在每天 \(time) 温和地提醒你打卡。首次开启时 macOS 会请求通知权限。"
        case .denied:
            return "通知权限已被拒绝。请前往「系统设置 → 通知 → LabForge」允许通知后再试。"
        case .authorized(let scheduled):
            if enabled && scheduled { return "已开启：每天 \(time) 提醒你进入实验室打卡。" }
            if enabled { return "已获通知授权，但提醒尚未排程，请重新切换一次开关。" }
            return "已获通知授权，当前未开启每日提醒。"
        case .error(let message):
            return "设置提醒失败：\(message)"
        }
    }
}
