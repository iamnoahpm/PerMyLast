import Foundation
import Testing
@testable import PerMyLastCore

private let modes = PresetLibrary.defaultModes
private let defaults = PresetLibrary.defaultPresets

/// Edit rows that change nothing, so a test can tweak just the row it cares about.
private func passthrough(_ list: [Preset], tweak: (Preset, inout PresetEdit) -> Void = { _, _ in }) -> [PresetEdit] {
    list.map { p in
        var e = PresetEdit(originalLabel: p.label, label: p.label, icon: p.icon, blurb: p.blurb,
                           prompt: p.prompt, isDefault: p.isDefault)
        tweak(p, &e)
        return e
    }
}

@Suite("validateLabel / normalizeCategory")
struct CategoryTests {
    @Test func rejectsBlankLabels() {
        #expect(!PresetLibrary.validateLabel(""))
        #expect(!PresetLibrary.validateLabel("   "))
        #expect(!PresetLibrary.validateLabel(nil))
        #expect(PresetLibrary.validateLabel("My Tone"))
    }

    @Test func passesValidCategoryThrough() {
        #expect(PresetLibrary.normalizeCategory("Reply", modes: modes) == "Reply")
    }

    @Test func fallsBackCaseInsensitively() {
        #expect(PresetLibrary.normalizeCategory("reply", modes: modes) == "Reply")
    }

    @Test func fallsBackToFirstModeForUnknown() {
        #expect(PresetLibrary.normalizeCategory("urgent", modes: modes) == "Reply")
        #expect(PresetLibrary.normalizeCategory(nil, modes: modes) == "Reply")
    }

    @Test func defaultsToDefaultModesWhenNoneGiven() {
        #expect(PresetLibrary.normalizeCategory("Write") == "Write")
        #expect(PresetLibrary.normalizeCategory("nope") == "Reply")
    }

    @Test func respectsCustomModes() {
        let custom = ["Work", "Personal"]
        #expect(PresetLibrary.normalizeCategory("Personal", modes: custom) == "Personal")
        #expect(PresetLibrary.normalizeCategory("Write", modes: custom) == "Work")
    }
}

@Suite("defaultPresets / normalize")
struct NormalizeTests {
    @Test func coversAllDefaultModes() {
        #expect(Set(defaults.map(\.category)) == Set(modes))
    }

    @Test func hasExactlyOneDefaultPerMode() {
        for mode in modes {
            #expect(defaults.filter { $0.category == mode && $0.isDefault }.count == 1)
        }
    }

    @Test func everyBuiltInHasIconAndOriginalPrompt() {
        for p in defaults {
            #expect(!p.icon.isEmpty)
            #expect(p.originalPrompt == p.prompt)
            #expect(p.uses == 0)
        }
    }

    @Test func fillsFieldsForLegacyPresets() throws {
        let json = #"[{"label":"Old Tone","prompt":"Be old:","isEmail":false}]"#
        let legacy = try JSONDecoder().decode([Preset].self, from: Data(json.utf8))
        let result = PresetLibrary.normalize(legacy, modes: modes)
        #expect(result == [Preset(label: "Old Tone", category: "Reply", icon: "", blurb: "", tone: "",
                                  prompt: "Be old:", originalPrompt: "Be old:", uses: 0,
                                  isEmail: false, isDefault: true, requiresMotherLanguage: false)])
    }

    @Test func demotesAllButFirstDefaultInACategory() {
        let list = [
            Preset(label: "A", category: "Write", prompt: "a", isDefault: true),
            Preset(label: "B", category: "Write", prompt: "b", isDefault: true)
        ]
        let result = PresetLibrary.normalize(list, modes: modes)
        #expect(result.filter(\.isDefault).map(\.label) == ["A"])
    }

    @Test func promotesFirstPresetWhenNoneMarked() {
        let list = [
            Preset(label: "A", category: "Write", prompt: "a"),
            Preset(label: "B", category: "Write", prompt: "b")
        ]
        let result = PresetLibrary.normalize(list, modes: modes)
        #expect(result.first(where: \.isDefault)?.label == "A")
    }

    @Test func supportsAnEmptyTab() {
        let result = PresetLibrary.normalize(defaults, modes: modes + ["New tab"])
        #expect(!result.contains { $0.category == "New tab" })
        #expect(result.count == defaults.count)
    }
}

@Suite("upsert / delete / incrementUses")
struct MutationTests {
    @Test func upsertAppendsNewLabel() {
        let next = PresetLibrary.upsert(defaults, draft: PresetDraft(label: "Blunt", category: "Write", blurb: "No sugarcoating", prompt: "Be blunt:"), modes: modes)
        let added = next.first { $0.label == "Blunt" }
        #expect(added?.category == "Write")
        #expect(added?.blurb == "No sugarcoating")
        #expect(added?.originalPrompt == "Be blunt:")
        #expect(next.filter { $0.category == "Write" && $0.isDefault }.count == 1)
    }

    @Test func upsertOverwritesInPlaceAndKeepsBaseline() {
        let next = PresetLibrary.upsert(defaults, draft: PresetDraft(label: "Email", category: "Reply", prompt: "New email tone:", isEmail: true), modes: modes)
        let found = next.first { $0.label == "Email" }
        #expect(found?.prompt == "New email tone:")
        #expect(found?.originalPrompt == defaults.first { $0.label == "Email" }?.originalPrompt)
        #expect(found?.tone == "Direct")
        #expect(next.count == defaults.count)
    }

    @Test func deleteRemovesNonDefault() {
        let after = PresetLibrary.delete(defaults, label: "Like Me", modes: modes)
        #expect(!after.contains { $0.label == "Like Me" })
        #expect(after.count == defaults.count - 1)
    }

    @Test func deleteIsNoOpForDefaultUnknownOrLastInTab() {
        #expect(PresetLibrary.delete(defaults, label: "Like Brit.", modes: modes) == defaults)
        #expect(PresetLibrary.delete(defaults, label: "Does Not Exist", modes: modes) == defaults)
        let onlyOne = defaults.filter { $0.category != "Understand" || $0.label == "Translate" }
        #expect(PresetLibrary.delete(onlyOne, label: "Translate", modes: modes) == onlyOne)
    }

    @Test func incrementUses() {
        let result = PresetLibrary.incrementUses(defaults, label: "Email")
        #expect(result.first { $0.label == "Email" }?.uses == 1)
        #expect(result.first { $0.label == "Message" }?.uses == 0)
        #expect(PresetLibrary.incrementUses(defaults, label: "Does Not Exist") == defaults)
    }
}

@Suite("applyEdits")
struct ApplyEditsTests {
    @Test func reordersToMatchIncoming() {
        let incoming = passthrough(Array(defaults.reversed()))
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        #expect(result.map(\.label) == defaults.reversed().map(\.label))
    }

    @Test func appliesPromptAndBlurbKeepingCategoryAndIsEmail() {
        let incoming = passthrough(defaults) { p, e in
            if p.label == "Like Brit." { e.prompt = "New rewrite prompt:"; e.blurb = "New blurb" }
        }
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        let rewrite = result.first { $0.label == "Like Brit." }
        #expect(rewrite?.prompt == "New rewrite prompt:")
        #expect(rewrite?.blurb == "New blurb")
        #expect(rewrite?.category == "Write")
        #expect(rewrite?.isEmail == false)
        #expect(rewrite?.originalPrompt == defaults.first { $0.label == "Like Brit." }?.originalPrompt)
    }

    @Test func renamesByOriginalLabel() {
        let incoming = passthrough(defaults) { p, e in
            if p.label == "Like Brit." { e.label = "Reword" }
        }
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        #expect(!result.contains { $0.label == "Like Brit." })
        let renamed = result.first { $0.label == "Reword" }
        #expect(renamed?.category == "Write")
        #expect(renamed?.isDefault == true)
    }

    @Test func movesTheDefaultFlag() {
        let incoming = passthrough(defaults) { p, e in
            e.isDefault = p.label == "Like Me" ? true : (p.category == "Write" ? false : p.isDefault)
        }
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        #expect(result.first { $0.label == "Like Me" }?.isDefault == true)
        #expect(result.first { $0.label == "Like Brit." }?.isDefault == false)
        #expect(result.filter { $0.category == "Write" && $0.isDefault }.count == 1)
    }

    @Test func ignoresUnknownOriginalLabels() {
        let incoming = [
            PresetEdit(originalLabel: "Like Brit.", label: "Like Brit.", prompt: "x", isDefault: true),
            PresetEdit(originalLabel: "Ghost Preset", label: "Ghost Preset", prompt: "should be dropped")
        ]
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        #expect(!result.contains { $0.label == "Ghost Preset" })
    }

    @Test func appendsStoredLabelsMissingFromIncoming() {
        let incoming = passthrough(defaults.filter { $0.label != "Explain" })
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        #expect(result.contains { $0.label == "Explain" })
        #expect(result.count == defaults.count)
    }

    @Test func iconCanBeCustomizedClearedOrKept() {
        let set = passthrough(defaults) { p, e in if p.label == "Like Brit." { e.icon = "🪄" } }
        #expect(PresetLibrary.applyEdits(stored: defaults, incoming: set, modes: modes).first { $0.label == "Like Brit." }?.icon == "🪄")
        let clear = passthrough(defaults) { p, e in if p.label == "Like Brit." { e.icon = "" } }
        #expect(PresetLibrary.applyEdits(stored: defaults, incoming: clear, modes: modes).first { $0.label == "Like Brit." }?.icon == "")
        let omit = passthrough(defaults) { _, e in e.icon = nil }
        #expect(PresetLibrary.applyEdits(stored: defaults, incoming: omit, modes: modes).first { $0.label == "Like Brit." }?.icon
                == defaults.first { $0.label == "Like Brit." }?.icon)
    }
}

@Suite("tabs (modes)")
struct ModeTests {
    @Test func addModePicksUniqueNames() {
        #expect(PresetLibrary.addMode(modes) == modes + ["New tab"])
        #expect(PresetLibrary.addMode(PresetLibrary.addMode(modes)) == modes + ["New tab", "New tab 2"])
    }

    @Test func renameCascadesOntoPresets() throws {
        let result = try #require(PresetLibrary.renameMode(modes, presets: defaults, from: "Write", to: "Compose"))
        #expect(result.modes == ["Reply", "Compose", "Understand"])
        #expect(result.presets.filter { $0.category == "Compose" }.count == defaults.filter { $0.category == "Write" }.count)
        #expect(!result.presets.contains { $0.category == "Write" })
    }

    @Test func renameRefusesBlankCollisionAndUnknown() {
        #expect(PresetLibrary.renameMode(modes, presets: defaults, from: "Write", to: "   ") == nil)
        #expect(PresetLibrary.renameMode(modes, presets: defaults, from: "Write", to: "Reply") == nil)
        #expect(PresetLibrary.renameMode(modes, presets: defaults, from: "Ghost", to: "Whatever") == nil)
    }

    @Test func renameToOwnNameIsAllowed() throws {
        let result = try #require(PresetLibrary.renameMode(modes, presets: defaults, from: "Write", to: "Write"))
        #expect(result.modes == modes)
    }

    @Test func deleteModeRemovesItsPresets() throws {
        let result = try #require(PresetLibrary.deleteMode(modes, presets: defaults, name: "Understand"))
        #expect(result.modes == ["Reply", "Write"])
        #expect(!result.presets.contains { $0.category == "Understand" })
    }

    @Test func deleteModeRefusesLastAndUnknown() {
        #expect(PresetLibrary.deleteMode(["Solo"], presets: [], name: "Solo") == nil)
        #expect(PresetLibrary.deleteMode(modes, presets: defaults, name: "Ghost") == nil)
    }

    @Test func reorderNeverDropsOrInventsATab() {
        #expect(PresetLibrary.reorderModes(modes, ordered: ["Understand", "Reply", "Write"]) == ["Understand", "Reply", "Write"])
        #expect(PresetLibrary.reorderModes(modes, ordered: ["Understand"]) == ["Understand", "Reply", "Write"])
        #expect(PresetLibrary.reorderModes(modes, ordered: ["Ghost", "Understand", "Reply", "Write"]) == ["Understand", "Reply", "Write"])
    }
}


@Suite("upgradeBuiltIns")
struct UpgradeBuiltInPromptTests {
    private let oldEmail = "You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a Direct tone."
    private let oldMessage = "Write a short, natural reply to this message. Keep it conversational and to the point."

    private func saved(_ label: String, prompt: String, original: String) -> [Preset] {
        var list = PresetLibrary.defaultPresets
        let i = list.firstIndex { $0.label == label }!
        list[i].prompt = prompt
        list[i].originalPrompt = original
        list[i].uses = 7
        return list
    }

    @Test func untouchedOldDefaultsBecomeTheNewOnes() throws {
        let list = saved("Email", prompt: oldEmail, original: oldEmail)
        let result = PresetLibrary.upgradeBuiltIns(list)
        let email = try #require(result.first { $0.label == "Email" })
        #expect(email.prompt == PresetLibrary.emailPrompt)
        #expect(email.originalPrompt == PresetLibrary.emailPrompt)
        #expect(email.uses == 7)   // everything else about the preset is kept
    }

    @Test func theEarlierNewEmailWordingIsUpgradedToo() throws {
        let previous = "You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a direct tone. Don't ever use \"—\" in the output."
        let list = saved("Email", prompt: previous, original: previous)
        let email = try #require(PresetLibrary.upgradeBuiltIns(list).first { $0.label == "Email" })
        #expect(email.prompt == PresetLibrary.emailPrompt)
        #expect(email.prompt.contains("{reply_intent}"))
    }

    @Test func aUserEditedPromptIsKeptButResetGoesToTheNewDefault() throws {
        let list = saved("Message", prompt: "My own message prompt", original: oldMessage)
        let message = try #require(PresetLibrary.upgradeBuiltIns(list).first { $0.label == "Message" })
        #expect(message.prompt == "My own message prompt")
        #expect(message.originalPrompt == PresetLibrary.messagePrompt)
    }

    @Test func isIdempotentAndLeavesCurrentAndCustomPresetsAlone() {
        let current = PresetLibrary.defaultPresets
        #expect(PresetLibrary.upgradeBuiltIns(current) == current)
        let once = PresetLibrary.upgradeBuiltIns(saved("Email", prompt: oldEmail, original: oldEmail))
        #expect(PresetLibrary.upgradeBuiltIns(once) == once)
        // A user's own preset that happens to be called "Email" with its own baseline is not touched.
        var custom = PresetLibrary.defaultPresets
        let i = custom.firstIndex { $0.label == "Email" }!
        custom[i].prompt = "custom"; custom[i].originalPrompt = "custom"
        #expect(PresetLibrary.upgradeBuiltIns(custom) == custom)
    }
}

@Suite("Write tab defaults and their upgrade")
struct WriteTabDefaultsTests {
    /// What earlier versions shipped for the Write tab.
    private func oldWriteTab() -> [Preset] {
        [
            Preset(label: "Rewrite like Native", category: "Write", icon: "\u{270D}\u{FE0F}", blurb: "Clear, native English level", tone: "Neutral",
                   prompt: "Rewrite this text like a native English.", uses: 5, isDefault: true),
            Preset(label: "Rewrite Like Me", category: "Write", icon: "\u{1F64B}\u{200D}\u{2642}", blurb: "Match my style, my English level", tone: "Personal",
                   prompt: "Rewrite this text like me.", uses: 2),
            Preset(label: "Fix Grammar", category: "Write", icon: "🔤", blurb: "Spelling and grammar only", tone: "Neutral",
                   prompt: "Fix grammar and spelling."),
            Preset(label: "Professional", category: "Write", icon: "👔", blurb: "Raise the register", tone: "Formal",
                   prompt: "Make this more professional.")
        ]
    }

    @Test func theWriteTabNowHasTwoPresets() {
        let write = PresetLibrary.defaultPresets.filter { $0.category == "Write" }
        #expect(write.map(\.label) == ["Like Brit.", "Like Me"])
        #expect(write.map(\.icon) == ["🤴", "🫆"])
        #expect(write.first?.isDefault == true)
    }

    @Test func savedCopiesAreRenamedAndTheDroppedOnesRemoved() throws {
        let result = PresetLibrary.upgradeBuiltIns(oldWriteTab())
        #expect(result.map(\.label) == ["Like Brit.", "Like Me"])
        let brit = try #require(result.first)
        #expect(brit.icon == "🤴")
        #expect(brit.uses == 5)          // history is kept
        #expect(brit.prompt == PresetLibrary.likeBritPrompt)
        #expect(brit.isDefault)
        #expect(result[1].icon == "🫆")
        #expect(result[1].uses == 2)
        #expect(result[1].prompt == PresetLibrary.likeMePrompt)
        #expect(result[1].originalPrompt == PresetLibrary.likeMePrompt)
    }

    @Test func theNewPromptsAreTheCasualTeamsWording() {
        let write = PresetLibrary.defaultPresets.filter { $0.category == "Write" }
        #expect(write[0].prompt == "Rewrite this as a casual Teams message. Native English, direct and confident. Fix grammar, phrasing, and flow only — keep the original content intact. Only break lines where it genuinely helps readability. No em dashes.")
        #expect(write[1].prompt == "Rewrite this as a casual Teams message. Direct and confident. Fix grammar, phrasing, and flow only — keep the original content intact. Only break lines where it genuinely helps readability. No em dashes.")
    }

    @Test func anEditedWritePromptSurvivesTheRename() throws {
        var list = oldWriteTab()
        list[0].prompt = "My own rewrite rules."
        let brit = try #require(PresetLibrary.upgradeBuiltIns(list).first { $0.label == "Like Brit." })
        #expect(brit.prompt == "My own rewrite rules.")
        #expect(brit.originalPrompt == PresetLibrary.likeBritPrompt)   // Reset to original gives the new default
    }

    @Test func aDroppedPresetTheUserEditedIsKept() throws {
        var list = oldWriteTab()
        list[2].prompt = "Fix grammar, keep my slang."   // user edited Fix Grammar
        let result = PresetLibrary.upgradeBuiltIns(list)
        #expect(result.contains { $0.label == "Fix Grammar" })
        #expect(!result.contains { $0.label == "Professional" })
    }

    @Test func aCustomIconSurvivesTheRename() throws {
        var list = oldWriteTab()
        list[0].icon = "🪄"
        let result = PresetLibrary.upgradeBuiltIns(list)
        #expect(result.first { $0.label == "Like Brit." }?.icon == "🪄")
    }

    @Test func removingTheDefaultStillLeavesOneDefaultPerTab() {
        var list = oldWriteTab()
        list[0].isDefault = false
        list[2].isDefault = true                          // Fix Grammar was the default
        let normalized = PresetLibrary.normalize(PresetLibrary.upgradeBuiltIns(list), modes: PresetLibrary.defaultModes)
        #expect(normalized.filter { $0.category == "Write" && $0.isDefault }.count == 1)
    }

    @Test func isIdempotentAndNeverOverwritesAnExistingPreset() {
        let once = PresetLibrary.upgradeBuiltIns(oldWriteTab())
        #expect(PresetLibrary.upgradeBuiltIns(once) == once)
        var clash = oldWriteTab()
        clash.append(Preset(label: "Like Brit.", category: "Write", prompt: "my own"))
        let result = PresetLibrary.upgradeBuiltIns(clash)
        #expect(result.filter { $0.label == "Like Brit." }.count == 1)       // no duplicate label
        #expect(result.contains { $0.label == "Rewrite like Native" })        // left alone instead of colliding
    }
}
