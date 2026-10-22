import AppKit
import SwiftUI

@main
struct PerMyLastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar icon is an NSStatusItem (see StatusItemController). SwiftUI
        // still wants a scene, so this one is never inserted.
        MenuBarExtra("Per My Last", isInserted: .constant(false)) { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { WindowCoordinator.shared.showSettings() }
                        .keyboardShortcut(",")
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PMLFontRegistration.register()
        Task { @MainActor in
            StatusItemController.shared.install()
            AppModel.shared.applyDockVisibility()
            AppModel.shared.applyShortcut()
            PurchaseService.shared.startListening()
            Task { @MainActor in
                await AccountModel.shared.startTrialIfNeeded()
                await AccountModel.shared.refreshEntitlement()
            }

            // Dev aids: PML_SHOW_POPUP=1 / PML_SHOW_SETTINGS=1 open a window at launch.
            let env = ProcessInfo.processInfo.environment
            // PML_APPEARANCE=dark|light forces the appearance, to check both themes without changing the system setting.
            if let name = env["PML_APPEARANCE"] { NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua) }
            if env["PML_SHOW_POPUP"] == "1" { WindowCoordinator.shared.showPopup() }
            if env["PML_SHOW_SETTINGS"] == "1" { WindowCoordinator.shared.showSettings() }
            // First run opens Settings; otherwise the popup, as the Electron app did.
            WindowCoordinator.shared.showMain()
        }
    }

    /// Closing the popup or Settings must not quit the app; it lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon, or opening the app again (Finder, Spotlight, `open`),
    /// should show a window instead of silently doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in WindowCoordinator.shared.showMain() }
        return false
    }
}
