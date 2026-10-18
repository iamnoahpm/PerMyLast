import Foundation

/// Pure functions over a preset list and its tab ("mode") list. Every mutation
/// funnels through `normalize`, so the invariants always hold: each preset's
/// category names a real tab, and each non-empty tab has exactly one default.
public enum PresetLibrary {
    /// Seed for a fresh install. Tabs are user-owned afterwards.
    public static let defaultModes = ["Reply", "Write", "Understand"]

    public static let motherLanguageToken = "{{motherLanguage}}"

    public static let emailPrompt = #"""
You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a direct tone. Don't ever use "—" in the output.

You will be given:
- ORIGINAL MESSAGE: the message being replied to (context only)
- REPLY INTENT: what the user actually wants to say

RULES:
1. REPLY INTENT is the source of truth for the content, meaning, and stance of the reply. Never override, soften, contradict, or "correct" it based on the ORIGINAL MESSAGE.
2. Do not answer the ORIGINAL MESSAGE directly if REPLY INTENT does not answer it directly. If REPLY INTENT is uncertain, deflects, or suggests an alternative path, the reply must preserve that same uncertainty or deflection, not resolve it into a confident yes/no.
3. Use the ORIGINAL MESSAGE only to determine tone and what the reply needs to respond to, not to determine what the reply should say.
4. The user is the one REPLYING, not the one being addressed. If the ORIGINAL MESSAGE opens with a greeting naming the user (e.g. "Hey Noah"), that name belongs to the user, the reply's sender, never the recipient. Do not copy, echo, or repurpose that greeting in the reply as if addressing someone. The reply should open naturally (a greeting to whoever sent the original message, no greeting at all, or straight into the content), never with the user's own name.
5. Write in a short, natural, conversational tone, as if the user is typing this themselves. No formal or corporate phrasing.
6. Keep it concise, one to three sentences unless REPLY INTENT clearly requires more.
7. Never use an em dash ("—") anywhere in the output.
8. Output only the reply text. No preamble, no explanation, no quotation marks around it.

ORIGINAL MESSAGE:
{original_message}

REPLY INTENT:
{reply_intent}
"""#

    public static let messagePrompt = #"""
You are drafting a reply to a message on the user's behalf. The user IS the person sending the reply.

You will be given:
- ORIGINAL MESSAGE: the message being replied to (context only)
- REPLY INTENT: what the user actually wants to say

RULES:
1. REPLY INTENT is the source of truth for the content, meaning, and stance of the reply. Never override, soften, contradict, or "correct" it based on the ORIGINAL MESSAGE.
2. Do not answer the ORIGINAL MESSAGE directly if REPLY INTENT does not answer it directly. If REPLY INTENT is uncertain, deflects, or suggests an alternative path, the reply must preserve that same uncertainty or deflection, not resolve it into a confident yes/no.
3. Use the ORIGINAL MESSAGE only to determine tone and what the reply needs to respond to, not to determine what the reply should say.
4. The user is the one REPLYING, not the one being addressed. If the ORIGINAL MESSAGE opens with a greeting naming the user (e.g. "Hey Noah"), that name belongs to the user, the reply's sender, never the recipient. Do not copy, echo, or repurpose that greeting in the reply as if addressing someone. The reply should open naturally (a greeting to whoever sent the original message, no greeting at all, or straight into the content), never with the user's own name.
5. Write in a short, natural, conversational tone, as if the user is typing this themselves. No formal or corporate phrasing.
6. Keep it concise, one to three sentences unless REPLY INTENT clearly requires more.
7. Never use an em dash ("—") anywhere in the output.
8. Output only the reply text. No preamble, no explanation, no quotation marks around it.

ORIGINAL MESSAGE:
{original_message}

REPLY INTENT:
{reply_intent}
"""#

    /// Built-in prompts that earlier versions shipped, by preset label. Saved
    /// copies still carrying one of these are moved to the current default.
    static let retiredDefaultPrompts: [String: [String]] = [
        "Email": [
            "You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a Direct tone.",
            "You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a direct tone. Don't ever use \"—\" in the output."
        ],
        "Message": ["Write a short, natural reply to this message. Keep it conversational and to the point."]
    ]

    public static let defaultPresets: [Preset] = [
        Preset(label: "Email", category: "Reply", icon: "📧", blurb: "Workplace email reply in your tone", tone: "Direct",
               prompt: emailPrompt,
               isEmail: true, isDefault: true),
        Preset(label: "Message", category: "Reply", icon: "💬", blurb: "Short chat / DM reply", tone: "Warm",
               prompt: messagePrompt),
        Preset(label: "Like Brit.", category: "Write", icon: "🤴", blurb: "Clear, native English level", tone: "Neutral",
               prompt: "Rewrite this text like a native English.", isDefault: true),
        Preset(label: "Like Me", category: "Write", icon: "🫆", blurb: "Match my style, my English level", tone: "Personal",
               prompt: "Rewrite this text like me."),
        Preset(label: "Explain", category: "Understand", icon: "💡", blurb: "Plain-language summary", tone: "Plain",
               prompt: "Explain this in simple terms.", isDefault: true),
        Preset(label: "Translate", category: "Understand", icon: "🌐", blurb: "Into {{motherLanguage}}", tone: "Neutral",
               prompt: "Translate this into {{motherLanguage}}", requiresMotherLanguage: true)
    ]

    /// Built-ins that were renamed (and given a new icon). Matched by the old label.
    static let renamedBuiltIns: [(from: String, to: String, oldIcon: String, newIcon: String)] = [
        ("Rewrite like Native", "Like Brit.", "\u{270D}\u{FE0F}", "🤴"),
        ("Rewrite Like Me", "Like Me", "\u{1F64B}\u{200D}\u{2642}", "🫆")
    ]

    /// Built-ins that were dropped from the defaults, with the prompt they shipped
    /// with. A saved copy is removed only if the user never edited it.
    static let removedBuiltIns: [(label: String, prompt: String)] = [
        ("Fix Grammar", "Fix grammar and spelling."),
        ("Professional", "Make this more professional.")
    ]

    /// Brings saved presets up to the current built-ins: new prompts, renamed
    /// actions, and dropped ones. Anything the user customised is kept: an edited
    /// prompt stays (Reset to original goes to the new default), an edited icon
    /// stays, and a dropped preset they changed isn't deleted. Safe to run repeatedly.
    public static func upgradeBuiltIns(_ list: [Preset]) -> [Preset] {
        var result = list.compactMap { p -> Preset? in
            if let gone = removedBuiltIns.first(where: { $0.label == p.label }),
               p.prompt == gone.prompt, p.originalPrompt == gone.prompt {
                return nil
            }
            return p
        }
        for rename in renamedBuiltIns {
            guard let i = result.firstIndex(where: { $0.label == rename.from }),
                  !result.contains(where: { $0.label == rename.to }) else { continue }
            result[i].label = rename.to
            if result[i].icon == rename.oldIcon { result[i].icon = rename.newIcon }
        }
        return result.map { p in
            guard let retired = retiredDefaultPrompts[p.label], retired.contains(p.originalPrompt),
                  let current = defaultPresets.first(where: { $0.label == p.label }) else { return p }
            var q = p
            if retired.contains(p.prompt) { q.prompt = current.prompt }
            q.originalPrompt = current.originalPrompt
            return q
        }
    }

    public static func validateLabel(_ label: String?) -> Bool {
        guard let label else { return false }
        return !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A category is valid as long as it names one of the caller's current
    /// tabs. Falls back case-insensitively first, then to the first tab.
    public static func normalizeCategory(_ category: String?, modes: [String]? = nil) -> String {
        let valid = (modes?.isEmpty == false) ? modes! : defaultModes
        if let category, valid.contains(category) { return category }
        if let category, let match = valid.first(where: { $0.lowercased() == category.lowercased() }) { return match }
        return valid[0]
    }

    public static func normalize(_ list: [Preset], modes: [String]? = nil) -> [Preset] {
        var result = list.map { p -> Preset in
            var q = p
            q.category = normalizeCategory(p.category, modes: modes)
            return q
        }
        var defaultSeen = Set<String>()
        result = result.map { p in
            var q = p
            if p.isDefault && !defaultSeen.contains(p.category) {
                defaultSeen.insert(p.category)
            } else {
                q.isDefault = false
            }
            return q
        }
        for i in result.indices {
            let category = result[i].category
            if defaultSeen.contains(category) { continue }
            if result.firstIndex(where: { $0.category == category }) == i {
                result[i].isDefault = true
                defaultSeen.insert(category)
            }
        }
        return result
    }

    /// Creates a preset, or overwrites in place when `draft.label` already
    /// exists (last write wins). On overwrite, `originalPrompt` and `uses`
    /// carry over from the stored record.
    public static func upsert(_ list: [Preset], draft: PresetDraft, modes: [String]? = nil) -> [Preset] {
        let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let idx = list.firstIndex(where: { $0.label == label })
        let stored = idx.map { list[$0] }
        let entry = Preset(
            label: label,
            category: normalizeCategory(draft.category, modes: modes),
            icon: draft.icon.trimmingCharacters(in: .whitespacesAndNewlines),
            blurb: draft.blurb.trimmingCharacters(in: .whitespacesAndNewlines),
            tone: draft.tone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? stored?.tone ?? "",
            prompt: draft.prompt,
            originalPrompt: stored?.originalPrompt ?? draft.prompt,
            uses: stored?.uses ?? 0,
            isEmail: draft.isEmail,
            isDefault: draft.isDefault,
            requiresMotherLanguage: draft.requiresMotherLanguage
        )
        var next = list
        if let idx { next[idx] = entry } else { next.append(entry) }
        return normalize(next, modes: modes)
    }

    /// A preset can't be deleted if it's its tab's default, or the only one
    /// left in that tab — every tab keeps at least one selectable action.
    public static func delete(_ list: [Preset], label: String, modes: [String]? = nil) -> [Preset] {
        guard let target = list.first(where: { $0.label == label }) else { return list }
        if target.isDefault { return list }
        let category = normalizeCategory(target.category, modes: modes)
        let siblings = list.filter { normalizeCategory($0.category, modes: modes) == category }.count
        if siblings <= 1 { return list }
        return normalize(list.filter { $0.label != label }, modes: modes)
    }

    /// Best-effort usage counter; an unknown label is a silent no-op.
    public static func incrementUses(_ list: [Preset], label: String) -> [Preset] {
        list.map { p in
            guard p.label == label else { return p }
            var q = p
            q.uses += 1
            return q
        }
    }

    /// Applies reorders/edits from the Settings editor. Category, isEmail,
    /// originalPrompt and uses always come from `stored`. Unknown
    /// `originalLabel`s are dropped; stored presets missing from `incoming`
    /// are appended so an edit pass can never silently lose one.
    public static func applyEdits(stored: [Preset], incoming: [PresetEdit], modes: [String]? = nil) -> [Preset] {
        var byLabel: [String: Preset] = [:]
        for p in stored { byLabel[p.label] = p }
        var seen = Set<String>()
        var result: [Preset] = []
        for entry in incoming {
            guard let base = byLabel[entry.originalLabel] else { continue }
            seen.insert(entry.originalLabel)
            let promptValid = !(entry.prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let newLabel = entry.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            result.append(Preset(
                label: newLabel.isEmpty ? base.label : newLabel,
                category: normalizeCategory(base.category, modes: modes),
                icon: entry.icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? base.icon,
                blurb: entry.blurb?.trimmingCharacters(in: .whitespacesAndNewlines) ?? base.blurb,
                tone: entry.tone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? base.tone,
                prompt: promptValid ? entry.prompt! : base.prompt,
                originalPrompt: base.originalPrompt,
                uses: base.uses,
                isEmail: base.isEmail,
                isDefault: entry.isDefault,
                requiresMotherLanguage: base.requiresMotherLanguage
            ))
        }
        for p in stored where !seen.contains(p.label) { result.append(p) }
        return normalize(result, modes: modes)
    }

    // MARK: Tabs ("modes")

    /// Appends a uniquely named tab: "New tab", "New tab 2", ...
    public static func addMode(_ modes: [String]) -> [String] {
        let base = "New tab"
        if !modes.contains(base) { return modes + [base] }
        var n = 2
        while modes.contains("\(base) \(n)") { n += 1 }
        return modes + ["\(base) \(n)"]
    }

    /// Renames a tab and every preset filed under it. Returns nil (leave state
    /// untouched) for a blank name, an unknown `from`, or a name collision.
    public static func renameMode(_ modes: [String], presets: [Preset], from: String, to: String)
        -> (modes: [String], presets: [Preset])? {
        let next = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty, modes.contains(from) else { return nil }
        if next != from && modes.contains(next) { return nil }
        let nextModes = modes.map { $0 == from ? next : $0 }
        let nextPresets = presets.map { p -> Preset in
            var q = p
            if p.category == from { q.category = next }
            return q
        }
        return (nextModes, normalize(nextPresets, modes: nextModes))
    }

    /// Deletes a tab and its presets. Refuses the last tab or an unknown name.
    public static func deleteMode(_ modes: [String], presets: [Preset], name: String)
        -> (modes: [String], presets: [Preset])? {
        guard modes.count > 1, modes.contains(name) else { return nil }
        let nextModes = modes.filter { $0 != name }
        let nextPresets = presets.filter { $0.category != name }
        return (nextModes, normalize(nextPresets, modes: nextModes))
    }

    /// Reorders tabs. Names missing from `ordered` are appended; names that
    /// aren't real tabs are ignored — a stale list can never drop or invent one.
    public static func reorderModes(_ modes: [String], ordered: [String]) -> [String] {
        let known = Set(modes)
        var next = ordered.filter { known.contains($0) }
        for m in modes where !next.contains(m) { next.append(m) }
        return next
    }
}
