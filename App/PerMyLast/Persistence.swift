import Foundation
import PerMyLastCore

struct AppSettings: Codable, Equatable {
    var model = ModelCatalog.defaultModel
    var effort = ModelCatalog.defaultEffort
    var workspaceId = ""
    /// Language that "Translate" targets, e.g. "Vietnamese". A Mac set to Vietnamese starts with
    /// Vietnamese so Translate works straight away; anyone else picks theirs in Settings.
    var motherLanguage = AppLanguage.detectDefault() == .vi ? "Vietnamese" : ""
    /// Whether the app also shows in the Dock (like the Electron version).
    var showInDock = true
    /// Advanced → Wartime / Peacetime mode configurator.
    var wartimePeacetimeEnabled = false
    /// Global hotkey as an accelerator string, e.g. "Command+Shift+W".
    var shortcut = "Command+Shift+W"
    /// Language of the app's own UI.
    var appLanguage = AppLanguage.detectDefault()
    /// Anonymous first-run funnel events (which setup step was reached; never text, email or keys).
    var shareAnonymousUsage = true

    init() {}

    /// Tolerant decoding: settings saved by an earlier build lack newer keys and
    /// must keep their saved values instead of resetting to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        // A custom model name saved by an earlier build is no longer offered; go back to the default.
        let saved = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        model = ModelCatalog.standardModels.contains { $0.id == saved } ? saved : d.model
        effort = try c.decodeIfPresent(Effort.self, forKey: .effort) ?? d.effort
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId) ?? d.workspaceId
        motherLanguage = try c.decodeIfPresent(String.self, forKey: .motherLanguage) ?? d.motherLanguage
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? d.showInDock
        wartimePeacetimeEnabled = try c.decodeIfPresent(Bool.self, forKey: .wartimePeacetimeEnabled) ?? d.wartimePeacetimeEnabled
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut) ?? d.shortcut
        appLanguage = try c.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? d.appLanguage
        shareAnonymousUsage = try c.decodeIfPresent(Bool.self, forKey: .shareAnonymousUsage) ?? d.shareAnonymousUsage
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
