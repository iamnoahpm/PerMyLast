// Generated from the Electron app's renderer/languages.js — reference list for the
// "mother language" picker. One representative flag per language; kept A-Z.
import Foundation

public struct Language: Equatable, Sendable, Identifiable {
    public let name: String
    public let flag: String
    public var id: String { name }
}

public enum Languages {
    public static let all: [Language] = [
        Language(name: "Afrikaans", flag: "🇿🇦"),
        Language(name: "Albanian", flag: "🇦🇱"),
        Language(name: "Amharic", flag: "🇪🇹"),
        Language(name: "Arabic", flag: "🇸🇦"),
        Language(name: "Armenian", flag: "🇦🇲"),
        Language(name: "Azerbaijani", flag: "🇦🇿"),
        Language(name: "Basque", flag: "🇪🇸"),
        Language(name: "Belarusian", flag: "🇧🇾"),
        Language(name: "Bengali", flag: "🇧🇩"),
        Language(name: "Bosnian", flag: "🇧🇦"),
        Language(name: "Bulgarian", flag: "🇧🇬"),
        Language(name: "Burmese", flag: "🇲🇲"),
        Language(name: "Catalan", flag: "🇪🇸"),
        Language(name: "Cebuano", flag: "🇵🇭"),
        Language(name: "Chinese (Simplified)", flag: "🇨🇳"),
        Language(name: "Chinese (Traditional)", flag: "🇹🇼"),
        Language(name: "Croatian", flag: "🇭🇷"),
        Language(name: "Czech", flag: "🇨🇿"),
        Language(name: "Danish", flag: "🇩🇰"),
        Language(name: "Dutch", flag: "🇳🇱"),
        Language(name: "English", flag: "🇬🇧"),
        Language(name: "Estonian", flag: "🇪🇪"),
        Language(name: "Filipino", flag: "🇵🇭"),
        Language(name: "Finnish", flag: "🇫🇮"),
        Language(name: "French", flag: "🇫🇷"),
        Language(name: "Georgian", flag: "🇬🇪"),
        Language(name: "German", flag: "🇩🇪"),
        Language(name: "Greek", flag: "🇬🇷"),
        Language(name: "Gujarati", flag: "🇮🇳"),
        Language(name: "Hausa", flag: "🇳🇬"),
        Language(name: "Hebrew", flag: "🇮🇱"),
        Language(name: "Hindi", flag: "🇮🇳"),
        Language(name: "Hungarian", flag: "🇭🇺"),
        Language(name: "Icelandic", flag: "🇮🇸"),
        Language(name: "Indonesian", flag: "🇮🇩"),
        Language(name: "Irish", flag: "🇮🇪"),
        Language(name: "Italian", flag: "🇮🇹"),
        Language(name: "Japanese", flag: "🇯🇵"),
        Language(name: "Javanese", flag: "🇮🇩"),
        Language(name: "Kannada", flag: "🇮🇳"),
        Language(name: "Kazakh", flag: "🇰🇿"),
        Language(name: "Khmer", flag: "🇰🇭"),
        Language(name: "Korean", flag: "🇰🇷"),
        Language(name: "Lao", flag: "🇱🇦"),
        Language(name: "Latvian", flag: "🇱🇻"),
        Language(name: "Lithuanian", flag: "🇱🇹"),
        Language(name: "Macedonian", flag: "🇲🇰"),
        Language(name: "Malay", flag: "🇲🇾"),
        Language(name: "Malayalam", flag: "🇮🇳"),
        Language(name: "Marathi", flag: "🇮🇳"),
        Language(name: "Mongolian", flag: "🇲🇳"),
        Language(name: "Nepali", flag: "🇳🇵"),
        Language(name: "Norwegian", flag: "🇳🇴"),
        Language(name: "Persian (Farsi)", flag: "🇮🇷"),
        Language(name: "Polish", flag: "🇵🇱"),
        Language(name: "Portuguese", flag: "🇵🇹"),
        Language(name: "Punjabi", flag: "🇮🇳"),
        Language(name: "Romanian", flag: "🇷🇴"),
        Language(name: "Russian", flag: "🇷🇺"),
        Language(name: "Serbian", flag: "🇷🇸"),
        Language(name: "Sinhala", flag: "🇱🇰"),
        Language(name: "Slovak", flag: "🇸🇰"),
        Language(name: "Slovenian", flag: "🇸🇮"),
        Language(name: "Spanish", flag: "🇪🇸"),
        Language(name: "Swahili", flag: "🇰🇪"),
        Language(name: "Swedish", flag: "🇸🇪"),
        Language(name: "Tamil", flag: "🇮🇳"),
        Language(name: "Telugu", flag: "🇮🇳"),
        Language(name: "Thai", flag: "🇹🇭"),
        Language(name: "Turkish", flag: "🇹🇷"),
        Language(name: "Ukrainian", flag: "🇺🇦"),
        Language(name: "Urdu", flag: "🇵🇰"),
        Language(name: "Uzbek", flag: "🇺🇿"),
        Language(name: "Vietnamese", flag: "🇻🇳"),
        Language(name: "Welsh", flag: "🇬🇧"),
        Language(name: "Zulu", flag: "🇿🇦")
    ]

    /// Substring match (not just prefix) so "ese" still finds "Chinese",
    /// "Japanese", "Vietnamese". Results stay A-Z since `all` already is.
    public static func find(_ query: String, limit: Int? = nil) -> [Language] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let matches = all.filter { $0.name.lowercased().contains(q) }
        if let limit { return Array(matches.prefix(limit)) }
        return matches
    }
}
