import AppKit
import PerMyLastCore
import SwiftUI

/// Records a global shortcut. Unlike the Electron version (a web page that
/// could only see keys the page received), this listens at the app level, so it
/// also catches combos like ⌘Q and swallows them instead of triggering them.
@MainActor
final class ShortcutRecorder: ObservableObject {
    enum Note: Equatable {
        case systemConflict(String)
        case appConflict(app: String, description: String)
        case needsModifier
        case required
    }

    @Published var recording = false
    @Published var note: Note?
    private var monitor: Any?

    func toggle() {
        if recording { stop() } else { start() }
    }

    func start() {
        guard !recording else { return }
        recording = true
        note = nil
        // The live hotkey must be out of the way, or pressing the same combo
        // would trigger it instead of being recorded.
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil // swallow everything while recording
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        AppModel.shared.applyShortcut() // resume whatever is saved
    }

    func clear() {
        if recording { stop() }
        note = .required // the saved shortcut stays active until a new one is recorded
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isEmpty { stop(); return } // Esc cancels

        guard let combo = KeyCombo(
            keyCode: Int(event.keyCode),
            command: flags.contains(.command), shift: flags.contains(.shift),
            option: flags.contains(.option), control: flags.contains(.control)
        ) else {
            note = .needsModifier
            return
        }

        if let conflict = ShortcutConflicts.find(combo.accelerator, scope: .system) {
            note = .systemConflict(conflict.description)
            stop()
            return
        }
        if let conflict = ShortcutConflicts.find(combo.accelerator, scope: .app) {
            note = .appConflict(app: conflict.app ?? "", description: conflict.description)
        } else {
            note = nil
        }
        AppModel.shared.settings.shortcut = combo.accelerator // saved → registered by the model
        stop()
    }
}

struct ShortcutRecorderRow: View {
    @Environment(AppModel.self) private var model
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Global shortcut")
                Spacer()
                Button {
                    recorder.toggle()
                } label: {
                    Group {
                        if recorder.recording { Text("Press a key combo… (Esc to cancel)") }
                        else { Text(verbatim: model.shortcutDisplay) }
                    }
                    .frame(minWidth: 160)
                }
                .help("Click here, then press a key combo…")
                Button { recorder.clear() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(PMLGhostButtonStyle())
                    .help("Clear")
            }
            Text("Copy some text, then press \(model.shortcutDisplay) anywhere to open it in Per My Last.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            Text("To skip copying, select text and use Services → Open in Per My Last. Give it a shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            if let error = model.hotKeyError {
                Text(error).font(PMLFont.hint).foregroundStyle(PMLColor.danger)
            }
            noteView
        }
        .onDisappear { if recorder.recording { recorder.stop() } }
    }

    @ViewBuilder private var noteView: some View {
        switch recorder.note {
        case .systemConflict(let description):
            Text("This hotkey conflicts with \(description) — choose another before saving.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.danger)
        case .appConflict(let app, let description):
            Text("Heads up: this is also \(app)'s shortcut for \(description). It'll still save, but may not always reach Per My Last while that app is frontmost.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.warning)
        case .needsModifier:
            Text("Hold ⌘, ⌃ or ⌥ and press a key.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.warning)
        case .required:
            Text("⚠ A shortcut is required — record one above.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.danger)
        case nil:
            EmptyView()
        }
    }
}
