import Foundation
import PerMyLastCore

struct AppSettings: Codable, Equatable {
    var model = ModelCatalog.defaultModel
    var effort = ModelCatalog.defaultEffort
    var workspaceId = ""
    /// Language that "Translate" targets, e.g. "Vietnamese".
    var motherLanguage = ""
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
