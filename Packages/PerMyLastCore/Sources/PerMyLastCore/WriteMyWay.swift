import Foundation

/// Advanced → Write My Way: how the user likes to write. When enabled, actions
/// that opt in (see `Preset.usesWriteMyWay`) get these preferences appended to
/// their prompt, so rewrites come out in the user's tone, length and format.
public struct WriteMyWaySettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var englishLevelEnabled = false
    public var testType = "TOEIC"
    public var testScore = ""
    public var tone = "casual"
    public var customTone = ""
    public var length = "short"
    public var customLength = ""
    public var customLengthUnit = "words"
    public var format = "message"

    public init() {}

    /// Tolerant: settings saved by earlier builds keep their values.
    public init(from decoder: Decoder) throws {
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

    /// The text appended to a prompt, or nil when there is nothing to add
    /// (Write My Way off, or every choice empty). The wording says these choices
    /// win over the action's own style: the user set them deliberately.
    public func promptBlock(includeEnglishLevel: Bool) -> String? {
        guard enabled else { return nil }
        var lines: [String] = []

        switch tone {
        case "other":
            let custom = customTone.trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { lines.append("- Tone: \(custom).") }
        case "professional", "casual", "friendly", "persuasive":
            lines.append("- Tone: \(tone).")
        default: break
        }

        switch length {
        case "short": lines.append("- Length: short, a few sentences at most.")
        case "medium": lines.append("- Length: medium, one or two short paragraphs.")
        case "long": lines.append("- Length: long and detailed where the content calls for it.")
        case "custom":
            let amount = customLength.trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = Int(amount), n > 0 {
                lines.append("- Length: no more than \(n) \(customLengthUnit == "characters" ? "characters" : "words").")
            }
        default: break
        }

        switch format {
        case "bullets": lines.append("- Format: bullet points.")
        case "message": lines.append("- Format: a chat message (Teams or Slack style).")
        case "email": lines.append("- Format: an email.")
        case "essay": lines.append("- Format: an essay.")
        case "blog": lines.append("- Format: a blog post.")
        default: break
        }

        let score = testScore.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeEnglishLevel, englishLevelEnabled, !score.isEmpty {
            lines.append("- English level: the writer's English is around \(testType) \(score). Keep the vocabulary and sentence structure at that level, no fancier.")
        }

        guard !lines.isEmpty else { return nil }
        return "The writer's preferences (apply these; where they conflict with the style above, follow these):\n" + lines.joined(separator: "\n")
    }
}
