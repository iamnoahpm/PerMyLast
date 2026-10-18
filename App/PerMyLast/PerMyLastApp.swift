import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct PerMyLastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            Button("Open Per My Last") { WindowCoordinator.shared.showPopup() }
            Toggle("Enabled", isOn: $model.enabled)
            Divider()
            Button("Settings…") { WindowCoordinator.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Per My Last") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(model.enabled ? "TrayEnabled" : "TrayDisabled")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppModel.shared.applyDockVisibility() }
        let hotKey = HotKey { Task { @MainActor in AppModel.shared.handleHotKey() } }
        // ⌘⇧W, same default as the Electron app. A shortcut recorder comes later.
        let ok = hotKey.register(keyCode: kVK_ANSI_W, modifiers: cmdKey | shiftKey)
        self.hotKey = hotKey
        if !ok {
            Task { @MainActor in
                AppModel.shared.hotKeyError = "⌘⇧W is already used by another app."
            }
        }
        Task { @MainActor in
            // Dev aid: PML_SHOW_POPUP=1 opens the popup at launch.
            if ProcessInfo.processInfo.environment["PML_SHOW_POPUP"] == "1" { WindowCoordinator.shared.showPopup() }
            await AppModel.shared.loadAPIKey()
            if AppModel.shared.apiKey.isEmpty { WindowCoordinator.shared.showSettings() }
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
