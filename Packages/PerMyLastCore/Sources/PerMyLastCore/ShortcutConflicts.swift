import Foundation

public struct ShortcutConflict: Equatable, Sendable {
    public enum Scope: Sendable { case system, app }
    public let accelerator: String
    public let scope: Scope
    /// Only set for app-scope conflicts, e.g. "TextEdit, Preview, Pages".
    public let app: String?
    public let description: String
}

/// Known-conflict list for the global shortcut. Two tiers:
/// - `system`: macOS-level shortcuts. A match is a hard block.
/// - `app`: shortcuts owned by common apps. Advisory only: shown while recording
///   and as a banner in the popup for whatever shortcut is saved.
public enum ShortcutConflicts {
    public static let macOSSystem: [ShortcutConflict] = [
        .init(accelerator: "Command+Space", scope: .system, app: nil, description: "macOS's Spotlight Search"),
        .init(accelerator: "Command+Tab", scope: .system, app: nil, description: "macOS's App Switcher"),
        .init(accelerator: "Command+Shift+3", scope: .system, app: nil, description: "macOS's screenshot (entire screen)"),
        .init(accelerator: "Command+Shift+4", scope: .system, app: nil, description: "macOS's screenshot (selection)"),
        .init(accelerator: "Command+Shift+5", scope: .system, app: nil, description: "macOS's screenshot/screen recording tools"),
        .init(accelerator: "Command+Q", scope: .system, app: nil, description: "the standard \"Quit\" shortcut"),
        .init(accelerator: "Command+H", scope: .system, app: nil, description: "the standard \"Hide\" shortcut"),
        .init(accelerator: "Command+M", scope: .system, app: nil, description: "the standard \"Minimize\" shortcut"),
        .init(accelerator: "Command+W", scope: .system, app: nil, description: "the standard \"Close Window\" shortcut"),
        .init(accelerator: "Command+,", scope: .system, app: nil, description: "the standard \"Preferences\" shortcut"),
        .init(accelerator: "Command+Option+Escape", scope: .system, app: nil, description: "macOS's Force Quit dialog"),
        .init(accelerator: "Control+Command+Q", scope: .system, app: nil, description: "macOS's Lock Screen"),
        .init(accelerator: "Control+Up", scope: .system, app: nil, description: "macOS's Mission Control"),
        .init(accelerator: "Control+Down", scope: .system, app: nil, description: "macOS's App Exposé")
    ]

    public static let commonApps: [ShortcutConflict] = [
        .init(accelerator: "Command+Shift+S", scope: .app, app: "TextEdit, Preview, Pages", description: "\"Duplicate\" / \"Save As\""),
        .init(accelerator: "Command+Shift+N", scope: .app, app: "Chrome and most browsers", description: "\"New Incognito/Private Window\""),
        .init(accelerator: "Command+Shift+T", scope: .app, app: "Chrome and most browsers", description: "\"Reopen Closed Tab\"")
    ]

    /// Order-insensitive, case-insensitive form used for comparison.
    static func normalize(_ accelerator: String) -> String {
        accelerator.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .sorted()
            .joined(separator: "+")
    }

    /// `scope == nil` checks both tiers.
    public static func find(_ accelerator: String, scope: ShortcutConflict.Scope? = nil) -> ShortcutConflict? {
        let target = normalize(accelerator)
        var candidates: [ShortcutConflict] = []
        if scope != .app { candidates += macOSSystem }
        if scope != .system { candidates += commonApps }
        return candidates.first { normalize($0.accelerator) == target }
    }

    /// "Control+Command+Shift+S" → "⌃⌘⇧S" (Apple's symbol order).
    public static func display(_ accelerator: String) -> String {
        var parts = accelerator.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // A literal "+" key ends the string ("Command++").
        guard let key = parts.popLast() else { return accelerator }
        let symbols: [(String, String)] = [("Control", "⌃"), ("Alt", "⌥"), ("Shift", "⇧"), ("Command", "⌘")]
        let mods = symbols.filter { parts.contains($0.0) }.map(\.1).joined()
        return mods + key
    }
}
