import AppKit
import LabForgeCore
import SwiftUI

/// AppKit delegate: keeps the menu bar extra alive after the main window closes, reopens the
/// dashboard on Dock click, and shuts the view model down cleanly on termination.
@MainActor
final class LabForgeAppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = LabForgeViewModel()

    /// Installed by a SwiftUI view that owns `openWindow`.
    var openDashboard: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.applicationDidFinishLaunching()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showDashboard() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.shutdown()
    }

    /// Brings the existing dashboard window forward, or asks SwiftUI to open it.
    func showDashboard() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains(LabForgeApp.dashboardID) == true }),
           window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openDashboard?()
        }
        NSApp.activate()
    }
}

@main
struct LabForgeApp: App {
    static let dashboardID = "dashboard"

    @NSApplicationDelegateAdaptor(LabForgeAppDelegate.self) private var appDelegate

    var body: some Scene {
        let viewModel = appDelegate.viewModel

        Window("LabForge 研铸", id: Self.dashboardID) {
            MainWorkbenchView()
                .environment(viewModel)
                .frame(minWidth: 880, minHeight: 620)
                .preferredColorScheme(viewModel.preferredColorScheme)
        }
        .defaultSize(width: 1080, height: 740)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarPopoverView()
                .environment(viewModel)
                .preferredColorScheme(viewModel.preferredColorScheme)
        } label: {
            MenuBarLabel(viewModel: viewModel, appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Status-bar label. Also hands SwiftUI's `openWindow` to the app delegate for Dock reopen.
private struct MenuBarLabel: View {
    let viewModel: LabForgeViewModel
    let appDelegate: LabForgeAppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(viewModel.menuBarTitle)
            .monospacedDigit()
            .onAppear {
                let open = openWindow
                appDelegate.openDashboard = { open(id: LabForgeApp.dashboardID) }
            }
    }
}
