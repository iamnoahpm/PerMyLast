import Foundation

/// One action in the "Help me" picker. Presets live under a user-owned tab
/// (`category`); see `PresetLibrary` for the rules that keep a list valid.
public struct Preset: Codable, Equatable, Sendable, Identifiable {
    public var label: String
    public var category: String
    public var icon: String
    public var blurb: String
    public var tone: String
    public var prompt: String
    /// Baseline the "Edited" pill and "Reset to original" compare against.
    public var originalPrompt: String
    public var uses: Int
    public var isEmail: Bool
    public var isDefault: Bool
    public var requiresMotherLanguage: Bool
    /// Adds the user's Advanced → Write My Way choices (tone, length, format) to this action's prompt.
    public var usesWriteMyWay: Bool
    /// With the above, also tells the model the user's English level, so the result stays at it.
    public var matchesEnglishLevel: Bool

    public var id: String { label }

    public init(
        label: String, category: String, icon: String = "", blurb: String = "",
        tone: String = "", prompt: String, originalPrompt: String? = nil, uses: Int = 0,
        isEmail: Bool = false, isDefault: Bool = false, requiresMotherLanguage: Bool = false,
        usesWriteMyWay: Bool = false, matchesEnglishLevel: Bool = false
    ) {
        self.label = label
        self.category = category
        self.icon = icon
        self.blurb = blurb
        self.tone = tone
        self.prompt = prompt
        self.originalPrompt = originalPrompt ?? prompt
        self.uses = uses
        self.isEmail = isEmail
        self.isDefault = isDefault
        self.requiresMotherLanguage = requiresMotherLanguage
        self.usesWriteMyWay = usesWriteMyWay
        self.matchesEnglishLevel = matchesEnglishLevel
    }

    private enum CodingKeys: String, CodingKey {
        case label, category, icon, blurb, tone, prompt, originalPrompt, uses
        case isEmail, isDefault, requiresMotherLanguage, usesWriteMyWay, matchesEnglishLevel
    }

    /// Tolerant on purpose: presets saved by older versions of the app lack most
    /// of these fields, and must still load (as "not edited", zero uses).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let label = try c.decode(String.self, forKey: .label)
        let prompt = try c.decode(String.self, forKey: .prompt)
        self.init(
            label: label,
            category: (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "",
            icon: (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? "",
            blurb: (try? c.decodeIfPresent(String.self, forKey: .blurb)) ?? "",
            tone: (try? c.decodeIfPresent(String.self, forKey: .tone)) ?? "",
            prompt: prompt,
            originalPrompt: try? c.decodeIfPresent(String.self, forKey: .originalPrompt),
            uses: (try? c.decodeIfPresent(Int.self, forKey: .uses)) ?? 0,
            isEmail: (try? c.decodeIfPresent(Bool.self, forKey: .isEmail)) ?? false,
            isDefault: (try? c.decodeIfPresent(Bool.self, forKey: .isDefault)) ?? false,
            requiresMotherLanguage: (try? c.decodeIfPresent(Bool.self, forKey: .requiresMotherLanguage)) ?? false,
            usesWriteMyWay: (try? c.decodeIfPresent(Bool.self, forKey: .usesWriteMyWay)) ?? false,
            matchesEnglishLevel: (try? c.decodeIfPresent(Bool.self, forKey: .matchesEnglishLevel)) ?? false
        )
    }
}

/// Input for creating or overwriting a preset. `tone == nil` means "keep the
/// stored tone on an overwrite" (and empty on a fresh insert).
public struct PresetDraft: Sendable {
    public var label: String
    public var category: String
    public var icon: String
    public var blurb: String
    public var tone: String?
    public var prompt: String
    public var isEmail: Bool
    public var isDefault: Bool
    public var requiresMotherLanguage: Bool
    public var usesWriteMyWay: Bool
    public var matchesEnglishLevel: Bool

    public init(
        label: String, category: String, icon: String = "", blurb: String = "",
        tone: String? = nil, prompt: String, isEmail: Bool = false,
        isDefault: Bool = false, requiresMotherLanguage: Bool = false,
        usesWriteMyWay: Bool = false, matchesEnglishLevel: Bool = false
    ) {
        self.label = label
        self.category = category
        self.icon = icon
        self.blurb = blurb
        self.tone = tone
        self.prompt = prompt
        self.isEmail = isEmail
        self.isDefault = isDefault
        self.requiresMotherLanguage = requiresMotherLanguage
        self.usesWriteMyWay = usesWriteMyWay
        self.matchesEnglishLevel = matchesEnglishLevel
    }
}

/// One row from the Settings preset editor. Matched to the stored preset by
/// `originalLabel` (the label as last persisted), so a pending rename can't
/// break identity mid-edit. `nil` fields keep the stored value.
public struct PresetEdit: Sendable {
    public var originalLabel: String
    public var label: String?
    public var icon: String?
    public var blurb: String?
    public var tone: String?
    public var prompt: String?
    public var isDefault: Bool
    public var usesWriteMyWay: Bool?
    public var matchesEnglishLevel: Bool?

    public init(
        originalLabel: String, label: String? = nil, icon: String? = nil, blurb: String? = nil,
        tone: String? = nil, prompt: String? = nil, isDefault: Bool = false,
        usesWriteMyWay: Bool? = nil, matchesEnglishLevel: Bool? = nil
    ) {
        self.originalLabel = originalLabel
        self.label = label
        self.icon = icon
        self.blurb = blurb
        self.tone = tone
        self.prompt = prompt
        self.isDefault = isDefault
        self.usesWriteMyWay = usesWriteMyWay
        self.matchesEnglishLevel = matchesEnglishLevel
    }
}
