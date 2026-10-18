import AppKit
import SwiftUI

/// Owns the two windows. They're AppKit windows hosting SwiftUI so the hotkey
/// (which has no SwiftUI view to call openWindow from) can show the popup.
@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()

    private var popup: NSWindow?
    private var settingsWindow: NSWindow?

    func showPopup() {
        let window = popup ?? makePopup()
        popup = window
        window.setFrame(dockedFrame(), display: true)
        present(window)
    }

    func hidePopup() { popup?.orderOut(nil) }

    func showSettings() {
        let window = settingsWindow ?? makeSettings()
        settingsWindow = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makePopup() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Per My Last"
        window.contentViewController = NSHostingController(rootView: MainView().environment(AppModel.shared))
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 380, height: 460)
        return window
    }

    private func makeSettings() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Per My Last Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView().environment(AppModel.shared))
        window.isReleasedWhenClosed = false
        window.center()
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
