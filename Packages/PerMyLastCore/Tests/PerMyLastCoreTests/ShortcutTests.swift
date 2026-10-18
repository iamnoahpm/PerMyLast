import Testing
@testable import PerMyLastCore

@Suite("ShortcutConflicts")
struct ShortcutConflictTests {
    @Test func flagsSystemShortcutsRegardlessOfOrderAndCase() {
        #expect(ShortcutConflicts.find("Command+Q")?.scope == .system)
        #expect(ShortcutConflicts.find("Q+Command")?.scope == .system)
        #expect(ShortcutConflicts.find("command+q")?.scope == .system)
    }

    @Test func flagsCommonAppShortcuts() {
        let result = ShortcutConflicts.find("Command+Shift+S")
        #expect(result?.scope == .app)
        #expect(result?.app?.contains("TextEdit") == true)
    }

    @Test func noConflictForAnUnusedCombo() {
        #expect(ShortcutConflicts.find("Control+Command+Shift+S") == nil)
        #expect(ShortcutConflicts.find("Command+Shift+W") == nil)
    }

    @Test func respectsTheScopeFilter() {
        #expect(ShortcutConflicts.find("Command+Q", scope: .app) == nil)
        #expect(ShortcutConflicts.find("Command+Shift+S", scope: .system) == nil)
    }

    @Test func displaysInAppleSymbolOrder() {
        #expect(ShortcutConflicts.display("Control+Command+Shift+S") == "⌃⇧⌘S")
        #expect(ShortcutConflicts.display("Command+Shift+W") == "⇧⌘W")
        #expect(ShortcutConflicts.display("Alt+Space") == "⌥Space")
    }
}

@Suite("KeyCombo")
struct KeyComboTests {
    @Test func parsesTheDefaultShortcut() throws {
        let combo = try #require(KeyCombo(accelerator: "Command+Shift+W"))
        #expect(combo.keyCode == 13)
        #expect(combo.modifiers == KeyCombo.command | KeyCombo.shift)
        #expect(combo.display == "⇧⌘W")
    }

    @Test func roundTripsThroughTheCanonicalForm() throws {
        for accelerator in ["Control+Command+Alt+Shift+K", "Command+Shift+W", "Alt+Space", "Command+F12", "Control+Up", "Command+,"] {
            let combo = try #require(KeyCombo(accelerator: accelerator))
            #expect(KeyCombo(accelerator: combo.accelerator) == combo)
        }
    }

    @Test func acceptsAliasesAndIgnoresCase() {
        #expect(KeyCombo(accelerator: "cmd+shift+w") == KeyCombo(accelerator: "Command+Shift+W"))
        #expect(KeyCombo(accelerator: "Option+Space") == KeyCombo(accelerator: "Alt+Space"))
    }

    @Test func rejectsBareKeysUnknownKeysAndBadModifiers() {
        #expect(KeyCombo(accelerator: "W") == nil)
        #expect(KeyCombo(accelerator: "Command+") == nil)
        #expect(KeyCombo(accelerator: "Command+Banana") == nil)
        #expect(KeyCombo(accelerator: "Hyper+W") == nil)
    }

    @Test func buildsFromRecorderEvents() throws {
        let combo = try #require(KeyCombo(keyCode: 13, command: true, shift: true, option: false, control: false))
        #expect(combo.accelerator == "Command+Shift+W")
        #expect(KeyCombo(keyCode: 13, command: false, shift: false, option: false, control: false) == nil)
        #expect(KeyCombo(keyCode: 999, command: true, shift: false, option: false, control: false) == nil)
    }
}

@Suite("AppLanguage")
struct AppLanguageTests {
    @Test func detectsVietnameseFromSystemLanguages() {
        #expect(AppLanguage.detectDefault(preferredLanguages: ["vi-VN", "en-US"]) == .vi)
        #expect(AppLanguage.detectDefault(preferredLanguages: ["en-GB"]) == .enUS)
        #expect(AppLanguage.detectDefault(preferredLanguages: []) == .enUS)
    }

    @Test func bothEnglishesUseTheEnglishStrings() {
        #expect(AppLanguage.enGB.resourceName == "en")
        #expect(AppLanguage.vi.resourceName == "vi")
    }
}
