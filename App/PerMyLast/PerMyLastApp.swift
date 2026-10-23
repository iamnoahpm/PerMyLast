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

/// Handles the "Per My Last" entry in the Services menu (declared as NSServices in Info.plist). macOS hands over the
/// selected text, so no Accessibility permission is needed, and the user can give it a shortcut in System Settings.
final class ServicesProvider: NSObject {
    @objc func openInPerMyLast(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string) else { return }
        Task { @MainActor in AppModel.shared.open(with: text) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
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
            // PML_ONBOARDING=1 restarts the first-run flow whatever this Mac already has set up.
            // PML_ONBOARDING_STEP=welcome|first_win|shortcut|access opens it at that step.
            if env["PML_ONBOARDING"] == "1" { OnboardingModel.shared.restart(at: OnboardingModel.Step(rawValue: env["PML_ONBOARDING_STEP"] ?? "") ?? .welcome) }
            if let dir = env["PML_SNAPSHOT"] { OnboardingSnapshots.write(to: dir); NSApp.terminate(nil) }
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

/// Dev aid: `PML_SNAPSHOT=1` writes each onboarding step in light and dark to PNG files and quits.
@MainActor
enum OnboardingSnapshots {
    static func write(to _: String) {
        // The app is sandboxed, so it writes into its own temp folder and prints where.
        let dir = NSTemporaryDirectory() + "pml-shots"
        print("SNAPSHOTS \(dir)")
        OnboardingView.snapshotMode = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for step in OnboardingModel.Step.allCases {
                OnboardingModel.shared.restart(at: step)
                let view = LocalizedRoot { OnboardingView() }
                    .environment(AppModel.shared).environment(AccountModel.shared)
                    .frame(width: 560, height: 900)
                    .background(PMLColor.surface)
                    .environment(\.colorScheme, scheme == "dark" ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(step.rawValue)-\(scheme).png"))
            }
        }
    }
}
