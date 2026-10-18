import Foundation
import PerMyLastCore

/// Owns the one global hotkey and re-registers it when the shortcut changes.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var hotKey: HotKey?
    private(set) var registered: String?

    /// Registers `accelerator`, replacing any previous hotkey. Returns false if
    /// it can't be parsed or another app already owns it.
    @discardableResult
    func apply(accelerator: String) -> Bool {
        hotKey = nil // unregisters
        registered = nil
        guard let combo = KeyCombo(accelerator: accelerator) else { return false }
        let newKey = HotKey { Task { @MainActor in AppModel.shared.handleHotKey() } }
        guard newKey.register(keyCode: combo.keyCode, modifiers: combo.modifiers) else { return false }
        hotKey = newKey
        registered = accelerator
        return true
    }

    /// While the recorder is listening, the live hotkey must be out of the way
    /// or pressing the same combo would trigger it instead of being recorded.
    func suspend() {
        hotKey = nil
        registered = nil
    }
}
