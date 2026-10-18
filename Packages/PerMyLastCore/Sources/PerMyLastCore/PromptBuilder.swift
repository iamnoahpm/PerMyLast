import Foundation

public struct ClaudeRequestContent: Equatable, Sendable {
    public let system: String
    public let content: String
}

public enum PromptBuilder {
    /// A prompt can be a full template: `{original_message}` is replaced with the
    /// text in the box, `{reply_intent}` with what the user typed as their intent.
    public static let originalMessageToken = "{original_message}"
    public static let replyIntentToken = "{reply_intent}"

    /// Stand-in when a template needs an intent and none was typed.
    static let noIntentPlaceholder = "(none given: write a short, natural reply that fits the message)"

    private static let textSystemPrompt = "You are a text processing assistant. Respond ONLY with the processed result, no preamble, explanation, or surrounding quotation marks."

    public static func buildRequest(text: String, prompt: String, isEmail: Bool) -> ClaudeRequestContent {
        // Template prompt: it already says where the message goes, so send it as is.
        if prompt.contains(originalMessageToken) {
            return ClaudeRequestContent(
                system: textSystemPrompt,
                content: prompt.replacingOccurrences(of: originalMessageToken, with: text))
        }
        if isEmail {
            return ClaudeRequestContent(
                system: "You are an email writing assistant. Write ONLY the reply email content, no preamble. Start with the greeting and end with a sign-off. Professional yet friendly unless told otherwise.",
                content: "Email to reply to:\n\(text)\n\nInstructions: \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        return ClaudeRequestContent(
            system: textSystemPrompt,
            content: "\(prompt)\n\nText: \(text)"
        )
    }

    /// `{{motherLanguage}}` is resolved at send time rather than stored in the
    /// prompt, so changing the Settings value takes effect without editing the
    /// preset. Only the first occurrence is replaced.
    public static func resolvedPrompt(_ preset: Preset, motherLanguage: String) -> String {
        guard preset.requiresMotherLanguage else { return preset.prompt }
        return replacingFirst(PresetLibrary.motherLanguageToken, in: preset.prompt,
                              with: motherLanguage.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Same substitution for the chip hint, with a readable stand-in when no
    /// language has been configured yet.
    public static func resolvedBlurb(_ preset: Preset, motherLanguage: String) -> String {
        guard preset.requiresMotherLanguage, preset.blurb.contains(PresetLibrary.motherLanguageToken) else {
            return preset.blurb
        }
        let lang = motherLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return replacingFirst(PresetLibrary.motherLanguageToken, in: preset.blurb,
                              with: lang.isEmpty ? "your language from Settings" : lang)
    }

    /// The prompt actually sent: the resolved preset prompt, plus the user's
    /// reply intent when the active tab takes one.
    public static func finalPrompt(preset: Preset, motherLanguage: String, intent: String?, tabTakesIntent: Bool) -> String {
        var prompt = resolvedPrompt(preset, motherLanguage: motherLanguage)
        let typed = tabTakesIntent ? (intent ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
        // A template places the intent itself; anything else gets it appended.
        if prompt.contains(replyIntentToken) {
            return prompt.replacingOccurrences(of: replyIntentToken, with: typed.isEmpty ? noIntentPlaceholder : typed)
        }
        if !typed.isEmpty { prompt += " " + typed }
        return prompt
    }

    private static func replacingFirst(_ target: String, in string: String, with replacement: String) -> String {
        guard let range = string.range(of: target) else { return string }
        return string.replacingCharacters(in: range, with: replacement)
    }
}
