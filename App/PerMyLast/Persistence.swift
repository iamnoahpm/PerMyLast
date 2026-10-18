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
