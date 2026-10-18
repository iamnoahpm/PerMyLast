import Foundation
import PerMyLastCore

struct AppSettings: Codable, Equatable {
    var model = ModelCatalog.defaultModel
    var effort = ModelCatalog.defaultEffort
    var workspaceId = ""
    /// Language that "Translate" targets, e.g. "Vietnamese".
    var motherLanguage = ""
    /// Whether the app also shows in the Dock (like the Electron version).
    var showInDock = true
    /// Advanced → Wartime / Peacetime mode configurator.
    var wartimePeacetimeEnabled = false
    /// Global hotkey as an accelerator string, e.g. "Command+Shift+W".
    var shortcut = "Command+Shift+W"
    /// Language of the app's own UI.
    var appLanguage = AppLanguage.detectDefault()

    init() {}

    /// Tolerant decoding: settings saved by an earlier build lack newer keys and
    /// must keep their saved values instead of resetting to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        effort = try c.decodeIfPresent(Effort.self, forKey: .effort) ?? d.effort
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId) ?? d.workspaceId
        motherLanguage = try c.decodeIfPresent(String.self, forKey: .motherLanguage) ?? d.motherLanguage
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        wartimePeacetimeEnabled = try c.decodeIfPresent(Bool.self, forKey: .wartimePeacetimeEnabled) ?? d.wartimePeacetimeEnabled
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut) ?? d.shortcut
        appLanguage = try c.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? d.appLanguage
    }
}

/// Advanced → Write My Way. Like the Electron app, this is a preview: the
/// choices are remembered but aren't sent with rewrites yet.
struct WriteMyWaySettings: Codable, Equatable {
    var enabled = false
    var englishLevelEnabled = false
    var testType = "TOEIC"
    var testScore = ""
    var tone = "professional"
    var customTone = ""
    var length = "short"
    var customLength = ""
    var customLengthUnit = "words"
    var format = "bullets"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WriteMyWaySettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        englishLevelEnabled = try c.decodeIfPresent(Bool.self, forKey: .englishLevelEnabled) ?? d.englishLevelEnabled
        testType = try c.decodeIfPresent(String.self, forKey: .testType) ?? d.testType
        testScore = try c.decodeIfPresent(String.self, forKey: .testScore) ?? d.testScore
        tone = try c.decodeIfPresent(String.self, forKey: .tone) ?? d.tone
        customTone = try c.decodeIfPresent(String.self, forKey: .customTone) ?? d.customTone
        length = try c.decodeIfPresent(String.self, forKey: .length) ?? d.length
        customLength = try c.decodeIfPresent(String.self, forKey: .customLength) ?? d.customLength
        customLengthUnit = try c.decodeIfPresent(String.self, forKey: .customLengthUnit) ?? d.customLengthUnit
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? d.format
    }
}

/// Small JSON-in-UserDefaults store for everything except the API key.
enum Persistence {
    static func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
