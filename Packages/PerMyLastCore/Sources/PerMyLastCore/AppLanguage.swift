import Foundation

/// The languages the app's own UI is available in.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case enUS = "en-US"
    case enGB = "en-GB"
    case vi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .enUS: return "🇺🇸 English (US)"
        case .enGB: return "🇬🇧 English (UK)"
        case .vi: return "🇻🇳 Tiếng Việt"
        }
    }

    /// Name of the `.lproj` folder with this language's strings.
    public var resourceName: String { self == .vi ? "vi" : "en" }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// Vietnamese if the Mac's first preferred language is Vietnamese, else US English.
    public static func detectDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        preferredLanguages.first?.lowercased().hasPrefix("vi") == true ? .vi : .enUS
    }
}
