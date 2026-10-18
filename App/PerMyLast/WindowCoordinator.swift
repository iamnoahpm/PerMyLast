import AppKit
import SwiftUI

/// Owns the two windows. They're AppKit windows hosting SwiftUI so the hotkey
/// (which has no SwiftUI view to call openWindow from) can show the popup.
///
/// Like the Electron version: both are ordinary windows (they go behind other
/// apps when you click away), and Settings opens in place of the popup, at its
/// size and position, then hands the screen back to the popup when it closes.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = WindowCoordinator()

    private var popup: NSWindow?
    private var settingsWindow: NSWindow?
    private var restorePopupWhenSettingsCloses = false

    func showPopup() {
        let window = popup ?? makePopup()
        popup = window
        // Settings replaces the popup while it's open; don't stack them.
        if let settings = settingsWindow, settings.isVisible { settings.close() }
        window.setFrame(dockedFrame(), display: true)
        present(window)
    }

    /// What "open the app" means: Settings until an API key exists, then the popup.
    func showMain() {
        if AppModel.shared.apiKey.isEmpty { showSettings() } else { showPopup() }
    }

    func hidePopup() { popup?.orderOut(nil) }

    func showSettings() {
        let window = settingsWindow ?? makeSettings()
        settingsWindow = window
        if window.isVisible {
            present(window)
            return
        }
        // Open exactly where the popup is (or would be), full-height, then hide it.
        let popupWasVisible = popup?.isVisible ?? false
        window.setFrame(popupWasVisible ? popup!.frame : dockedFrame(), display: true)
        restorePopupWhenSettingsCloses = popupWasVisible
        if popupWasVisible { popup?.orderOut(nil) }
        present(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow, restorePopupWhenSettingsCloses else { return }
        restorePopupWhenSettingsCloses = false
        if let popup { present(popup) }
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makePopup() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Per My Last"
        window.contentViewController = NSHostingController(rootView: LocalizedRoot { MainView() }.environment(AppModel.shared))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 380, height: 460)
        return window
    }

    private func makeSettings() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Per My Last Settings"
        window.contentViewController = NSHostingController(rootView: LocalizedRoot { SettingsView() }.environment(AppModel.shared))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 420, height: 520)
        window.delegate = self
        return window
    }

    /// Right half of whichever display the cursor is on, full height.
    private func dockedFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 960, height: 700)
        let width = max(area.width / 2, 420)
        return NSRect(x: area.maxX - width, y: area.minY, width: width, height: area.height)
    }
}
