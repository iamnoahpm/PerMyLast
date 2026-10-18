import Foundation

/// A global hotkey: a macOS virtual key code plus Carbon modifier flags.
/// Round-trips with accelerator strings like "Command+Shift+W", the format the
/// Electron app stored, so saved shortcuts and the conflict list keep working.
public struct KeyCombo: Equatable, Sendable {
    public static let command = 0x100, shift = 0x200, option = 0x800, control = 0x1000

    public let keyCode: Int
    public let modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// nil if the key isn't supported or no modifier was held (a bare key would
    /// swallow normal typing system-wide).
    public init?(keyCode: Int, command: Bool, shift: Bool, option: Bool, control: Bool) {
        var mods = 0
        if command { mods |= Self.command }
        if shift { mods |= Self.shift }
        if option { mods |= Self.option }
        if control { mods |= Self.control }
        guard mods != 0, Self.keyNames[keyCode] != nil else { return nil }
        self.init(keyCode: keyCode, modifiers: mods)
    }

    public init?(accelerator: String) {
        var parts = accelerator.split(separator: "+", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.popLast(), !keyName.isEmpty,
              let code = Self.keyCodes[keyName.uppercased()] ?? Self.keyCodes[keyName] else { return nil }
        var mods = 0
        for part in parts {
            switch part.lowercased() {
            case "command", "cmd", "meta": mods |= Self.command
            case "shift": mods |= Self.shift
            case "alt", "option": mods |= Self.option
            case "control", "ctrl": mods |= Self.control
            default: return nil
            }
        }
        guard mods != 0 else { return nil }
        self.init(keyCode: code, modifiers: mods)
    }

    /// Canonical accelerator, e.g. "Control+Command+Alt+Shift+W".
    public var accelerator: String {
        var parts: [String] = []
        if modifiers & Self.control != 0 { parts.append("Control") }
        if modifiers & Self.command != 0 { parts.append("Command") }
        if modifiers & Self.option != 0 { parts.append("Alt") }
        if modifiers & Self.shift != 0 { parts.append("Shift") }
        parts.append(Self.keyNames[keyCode] ?? "?")
        return parts.joined(separator: "+")
    }

    public var display: String { ShortcutConflicts.display(accelerator) }

    // MARK: Key table (ANSI layout virtual key codes)

    private static let table: [(String, Int)] = [
        ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("H", 4), ("G", 5), ("Z", 6), ("X", 7), ("C", 8), ("V", 9),
        ("B", 11), ("Q", 12), ("W", 13), ("E", 14), ("R", 15), ("Y", 16), ("T", 17),
        ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24), ("9", 25), ("7", 26),
        ("-", 27), ("8", 28), ("0", 29), ("]", 30), ("O", 31), ("U", 32), ("[", 33), ("I", 34), ("P", 35),
        ("Return", 36), ("L", 37), ("J", 38), ("'", 39), ("K", 40), (";", 41), ("\\", 42), (",", 43), ("/", 44),
        ("N", 45), ("M", 46), (".", 47), ("Tab", 48), ("Space", 49), ("Backspace", 51), ("Escape", 53),
        ("Delete", 117),
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F6", 97), ("F7", 98), ("F8", 100),
        ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111),
        ("Left", 123), ("Right", 124), ("Down", 125), ("Up", 126)
    ]
    static let keyCodes: [String: Int] = Dictionary(uniqueKeysWithValues: table.map { ($0.0.uppercased(), $0.1) })
    static let keyNames: [Int: String] = Dictionary(uniqueKeysWithValues: table.map { ($0.1, $0.0) })

    /// Whether the recorder can produce this key.
    public static func isSupported(keyCode: Int) -> Bool { keyNames[keyCode] != nil }
}
