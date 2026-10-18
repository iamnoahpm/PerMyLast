import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct PerMyLastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            Group {
            Button("Open Per My Last") { WindowCoordinator.shared.showPopup() }
            Toggle("Enabled", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
            Toggle("Show in Dock", isOn: Binding(get: { model.settings.showInDock }, set: { model.setShowInDock($0) }))
            Divider()
            Button("Settings…") { WindowCoordinator.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Per My Last") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
            }
            .environment(\.locale, model.locale)
        } label: {
            Image(model.enabled ? "TrayEnabled" : "TrayDisabled")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppModel.shared.applyDockVisibility()
            AppModel.shared.applyShortcut()
        }
        Task { @MainActor in
            // Dev aid: PML_SHOW_POPUP=1 opens the popup at launch.
            if ProcessInfo.processInfo.environment["PML_SHOW_POPUP"] == "1" { WindowCoordinator.shared.showPopup() }
            if ProcessInfo.processInfo.environment["PML_SHOW_SETTINGS"] == "1" { WindowCoordinator.shared.showSettings() }
            await AppModel.shared.loadAPIKey()
            // First run: Settings. Otherwise show the popup, as the Electron app did.
            if AppModel.shared.apiKey.isEmpty { WindowCoordinator.shared.showSettings() }
            else { WindowCoordinator.shared.showPopup() }
        }
    }

    /// Closing the popup or Settings must not quit the app; it lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon, or opening the app again (Finder, Spotlight, `open`),
    /// should show a window instead of silently doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            if AppModel.shared.apiKeyLoaded && AppModel.shared.apiKey.isEmpty {
                WindowCoordinator.shared.showSettings()
            } else {
                WindowCoordinator.shared.showPopup()
            }
        }
        return false
    }
}
