import AppKit

/// The icon in the menu bar. Left-click opens the app; right-click (or
/// Control-click) shows the options menu. SwiftUI's MenuBarExtra can't tell the
/// two apart, so this is a plain NSStatusItem.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var item: NSStatusItem?

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Per My Last"
        self.item = item
        refreshIcon()
    }

    /// Solid umbrella when enabled, hollow tilted one when off.
    func refreshIcon() {
        let image = NSImage(named: AppModel.shared.enabled ? "TrayEnabled" : "TrayDisabled")
        image?.isTemplate = true
        item?.button?.image = image
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let wantsMenu = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if wantsMenu { showMenu() } else { WindowCoordinator.shared.showMain() }
    }

    private func showMenu() {
        // Attaching the menu only for this click keeps left-click free for the app.
        item?.menu = makeMenu()
        item?.button?.performClick(nil)
        item?.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let model = AppModel.shared
        let menu = NSMenu()

        let enabled = NSMenuItem(title: L("Enabled"), action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.state = model.enabled ? .on : .off
        enabled.target = self
        menu.addItem(enabled)

        let dock = NSMenuItem(title: L("Show in Dock"), action: #selector(toggleDock), keyEquivalent: "")
        dock.state = model.settings.showInDock ? .on : .off
        dock.target = self
        menu.addItem(dock)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        if AccountModel.shared.isConfigured, AccountModel.shared.entitlement?.plan.isPro != true {
            let upgrade = NSMenuItem(title: L("Upgrade…"), action: #selector(openPaywall), keyEquivalent: "")
            upgrade.target = self
            menu.addItem(upgrade)
        }

        let updates = NSMenuItem(title: L("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("Quit Per My Last"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleEnabled() { AppModel.shared.setEnabled(!AppModel.shared.enabled) }
    @objc private func toggleDock() { AppModel.shared.setShowInDock(!AppModel.shared.settings.showInDock) }
    @objc private func openPaywall() { WindowCoordinator.shared.showPaywall() }
    @objc private func openSettings() { WindowCoordinator.shared.showSettings() }
    @objc private func checkForUpdates() { AppModel.shared.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}
