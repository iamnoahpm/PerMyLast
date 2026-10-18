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
        let after = PresetLibrary.delete(defaults, label: "Fix Grammar", modes: modes)
        #expect(!after.contains { $0.label == "Fix Grammar" })
        #expect(after.count == defaults.count - 1)
    }

    @Test func deleteIsNoOpForDefaultUnknownOrLastInTab() {
        #expect(PresetLibrary.delete(defaults, label: "Rewrite like Native", modes: modes) == defaults)
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
            if p.label == "Rewrite like Native" { e.prompt = "New rewrite prompt:"; e.blurb = "New blurb" }
        }
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        let rewrite = result.first { $0.label == "Rewrite like Native" }
        #expect(rewrite?.prompt == "New rewrite prompt:")
        #expect(rewrite?.blurb == "New blurb")
        #expect(rewrite?.category == "Write")
        #expect(rewrite?.isEmail == false)
        #expect(rewrite?.originalPrompt == defaults.first { $0.label == "Rewrite like Native" }?.originalPrompt)
    }

    @Test func renamesByOriginalLabel() {
        let incoming = passthrough(defaults) { p, e in
            if p.label == "Rewrite like Native" { e.label = "Reword" }
        }
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        #expect(!result.contains { $0.label == "Rewrite like Native" })
        let renamed = result.first { $0.label == "Reword" }
        #expect(renamed?.category == "Write")
        #expect(renamed?.isDefault == true)
    }

    @Test func movesTheDefaultFlag() {
        let incoming = passthrough(defaults) { p, e in
            e.isDefault = p.label == "Fix Grammar" ? true : (p.category == "Write" ? false : p.isDefault)
        }
        let result = PresetLibrary.applyEdits(stored: defaults, incoming: incoming, modes: modes)
        #expect(result.first { $0.label == "Fix Grammar" }?.isDefault == true)
        #expect(result.first { $0.label == "Rewrite like Native" }?.isDefault == false)
        #expect(result.filter { $0.category == "Write" && $0.isDefault }.count == 1)
    }

    @Test func ignoresUnknownOriginalLabels() {
        let incoming = [
            PresetEdit(originalLabel: "Rewrite like Native", label: "Rewrite like Native", prompt: "x", isDefault: true),
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
        let set = passthrough(defaults) { p, e in if p.label == "Rewrite like Native" { e.icon = "🪄" } }
        #expect(PresetLibrary.applyEdits(stored: defaults, incoming: set, modes: modes).first { $0.label == "Rewrite like Native" }?.icon == "🪄")
        let clear = passthrough(defaults) { p, e in if p.label == "Rewrite like Native" { e.icon = "" } }
        #expect(PresetLibrary.applyEdits(stored: defaults, incoming: clear, modes: modes).first { $0.label == "Rewrite like Native" }?.icon == "")
        let omit = passthrough(defaults) { _, e in e.icon = nil }
        #expect(PresetLibrary.applyEdits(stored: defaults, incoming: omit, modes: modes).first { $0.label == "Rewrite like Native" }?.icon
                == defaults.first { $0.label == "Rewrite like Native" }?.icon)
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
