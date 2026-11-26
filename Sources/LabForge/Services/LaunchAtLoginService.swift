import Foundation
import ServiceManagement

/// Safe wrapper around `SMAppService.mainApp`.
///
/// Only meaningful inside a `.app` bundle; ad-hoc signed builds may additionally require the user to
/// approve LabForge in「系统设置 → 通用 → 登录项」.
@MainActor
final class LaunchAtLoginService {

    enum Status: Equatable {
        case unavailable
        case enabled
        case requiresApproval
        case disabled
        case notFound
        case error(String)
    }

    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func currentStatus() -> Status {
        guard Self.isAvailable else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .notFound
        @unknown default: return .disabled
        }
    }

    /// Registers / unregisters the main app as a login item. Never throws; failures become `.error`.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Status {
        guard Self.isAvailable else { return .unavailable }
        do {
            if enabled {
                let status = SMAppService.mainApp.status
                if status != .enabled && status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
            return currentStatus()
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func description(for status: Status) -> String {
        switch status {
        case .unavailable:
            return "当前不是从 .app 包运行，无法注册登录项。请安装到 /Applications/LabForge.app 后再开启。"
        case .enabled:
            return "已开启：登录 macOS 后 LabForge 会自动出现在菜单栏。"
        case .requiresApproval:
            return "已提交登录项，但需要你在「系统设置 → 通用 → 登录项」中允许 LabForge（ad-hoc 签名应用常见）。"
        case .disabled:
            return "未开启。开启后 LabForge 将随系统登录自动启动。"
        case .notFound:
            return "系统未能识别本应用的登录项配置，请确认应用位于 /Applications 并重新开启。"
        case .error(let message):
            return "设置登录项失败：\(message)。ad-hoc 签名应用可能需要在「系统设置 → 通用 → 登录项」中手动添加。"
        }
    }
}
