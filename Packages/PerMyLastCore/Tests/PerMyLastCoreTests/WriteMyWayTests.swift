import Foundation
import Testing
@testable import PerMyLastCore

@Suite("Write My Way")
struct WriteMyWayTests {
    private func enabled(_ edit: (inout WriteMyWaySettings) -> Void = { _ in }) -> WriteMyWaySettings {
        var s = WriteMyWaySettings()
        s.enabled = true
        edit(&s)
        return s
    }

    @Test func offMeansNothingIsAdded() {
        #expect(WriteMyWaySettings().promptBlock(includeEnglishLevel: true) == nil)
    }

    @Test func listsToneLengthAndFormat() throws {
        let block = try #require(enabled { $0.tone = "friendly"; $0.length = "medium"; $0.format = "email" }.promptBlock(includeEnglishLevel: false))
        #expect(block.hasPrefix("The writer's preferences (apply these; where they conflict with the style above, follow these):"))
        #expect(block.contains("- Tone: friendly."))
        #expect(block.contains("- Length: medium, one or two short paragraphs."))
        #expect(block.contains("- Format: an email."))
        #expect(!block.contains("English level"))
    }

    @Test func englishLevelNeedsTheSwitchAScoreAndAnActionThatAsksForIt() throws {
        let on = enabled { $0.englishLevelEnabled = true; $0.testType = "IELTS"; $0.testScore = " 6.5 " }
        let withLevel = try #require(on.promptBlock(includeEnglishLevel: true))
        #expect(withLevel.contains("English level: the writer's English is around IELTS 6.5."))
        #expect(try #require(on.promptBlock(includeEnglishLevel: false)).contains("English level") == false)
        let noScore = enabled { $0.englishLevelEnabled = true; $0.testScore = "  " }
        #expect(try #require(noScore.promptBlock(includeEnglishLevel: true)).contains("English level") == false)
        let switchedOff = enabled { $0.englishLevelEnabled = false; $0.testScore = "850" }
        #expect(try #require(switchedOff.promptBlock(includeEnglishLevel: true)).contains("English level") == false)
    }

    @Test func customToneAndCustomLength() throws {
        let block = try #require(enabled {
            $0.tone = "other"; $0.customTone = "dry and a bit sarcastic"
            $0.length = "custom"; $0.customLength = "60"; $0.customLengthUnit = "characters"
        }.promptBlock(includeEnglishLevel: false))
        #expect(block.contains("- Tone: dry and a bit sarcastic."))
        #expect(block.contains("- Length: no more than 60 characters."))
    }

    @Test func emptyOrInvalidCustomValuesAreSkippedNotSentBlank() throws {
        let block = try #require(enabled {
            $0.tone = "other"; $0.customTone = "  "
            $0.length = "custom"; $0.customLength = "lots"
        }.promptBlock(includeEnglishLevel: false))
        #expect(!block.contains("Tone:"))
        #expect(!block.contains("Length:"))
        #expect(block.contains("Format:"))
    }

    @Test func savedSettingsFromEarlierBuildsStillLoad() throws {
        let old = #"{"enabled":true,"englishLevelEnabled":true,"testType":"SAT","testScore":"1350","tone":"professional","length":"long","format":"essay"}"#
        let s = try JSONDecoder().decode(WriteMyWaySettings.self, from: Data(old.utf8))
        #expect(s.enabled && s.englishLevelEnabled)
        #expect(s.testType == "SAT" && s.testScore == "1350")
        #expect(s.format == "essay" && s.customLengthUnit == "words")
    }
}

@Suite("Write My Way in prompts")
struct WriteMyWayPromptTests {
    private func preset(_ label: String) throws -> Preset {
        try #require(PresetLibrary.defaultPresets.first { $0.label == label })
    }
    private var settings: WriteMyWaySettings {
        var s = WriteMyWaySettings()
        s.enabled = true; s.englishLevelEnabled = true; s.testType = "TOEIC"; s.testScore = "850"
        return s
    }

    @Test func theWriteTabDefaultsOptIn() throws {
        let brit = try preset("Like Brit."), me = try preset("Like Me")
        #expect(brit.usesWriteMyWay && !brit.matchesEnglishLevel)   // "native English": don't pull it down to the user's level
        #expect(me.usesWriteMyWay && me.matchesEnglishLevel)
        #expect(!(try preset("Email")).usesWriteMyWay)
        #expect(!(try preset("Explain")).usesWriteMyWay)
    }

    @Test func likeMeGetsTheFullBlockAndLikeBritGetsItWithoutTheEnglishLevel() throws {
        let me = PromptBuilder.finalPrompt(preset: try preset("Like Me"), motherLanguage: "", intent: nil, tabTakesIntent: false, writeMyWay: settings)
        #expect(me.hasPrefix(PresetLibrary.likeMePrompt + "\n\nThe writer's preferences"))
        #expect(me.contains("English level: the writer's English is around TOEIC 850"))
        let brit = PromptBuilder.finalPrompt(preset: try preset("Like Brit."), motherLanguage: "", intent: nil, tabTakesIntent: false, writeMyWay: settings)
        #expect(brit.contains("- Tone: casual."))
        #expect(!brit.contains("English level"))
    }

    @Test func actionsThatDontOptInAreUntouched() throws {
        let explain = try preset("Explain")
        let prompt = PromptBuilder.finalPrompt(preset: explain, motherLanguage: "", intent: nil, tabTakesIntent: false, writeMyWay: settings)
        #expect(prompt == explain.prompt)
    }

    @Test func offOrMissingSettingsLeaveThePromptAlone() throws {
        let me = try preset("Like Me")
        #expect(PromptBuilder.finalPrompt(preset: me, motherLanguage: "", intent: nil, tabTakesIntent: false) == me.prompt)
        #expect(PromptBuilder.finalPrompt(preset: me, motherLanguage: "", intent: nil, tabTakesIntent: false, writeMyWay: WriteMyWaySettings()) == me.prompt)
        #expect(!PromptBuilder.appliesWriteMyWay(me, WriteMyWaySettings()))
        #expect(PromptBuilder.appliesWriteMyWay(me, settings))
    }

    @Test func aTemplatePresetThatOptsInGetsTheBlockAfterTheTemplate() throws {
        var email = try preset("Email")
        email.usesWriteMyWay = true
        let prompt = PromptBuilder.finalPrompt(preset: email, motherLanguage: "", intent: "decline", tabTakesIntent: true, writeMyWay: settings)
        #expect(prompt.contains("REPLY INTENT:\ndecline\n\nThe writer's preferences"))
    }

    @Test func flagsSurviveEditsAndRoundTrips() throws {
        let list = PresetLibrary.defaultPresets
        let edited = PresetLibrary.applyEdits(stored: list, incoming: list.map {
            PresetEdit(originalLabel: $0.label, label: $0.label, prompt: $0.prompt, isDefault: $0.isDefault,
                       usesWriteMyWay: $0.label == "Explain" ? true : nil)
        })
        #expect(edited.first { $0.label == "Explain" }?.usesWriteMyWay == true)
        #expect(edited.first { $0.label == "Like Me" }?.matchesEnglishLevel == true)   // nil keeps the stored value
        let json = try JSONEncoder().encode(edited)
        #expect(try JSONDecoder().decode([Preset].self, from: json) == edited)
    }

    @Test func oneTimeStepSwitchesItOnForSavedBuiltInsOnly() throws {
        var saved = PresetLibrary.defaultPresets
        for i in saved.indices { saved[i].usesWriteMyWay = false; saved[i].matchesEnglishLevel = false }
        let result = PresetLibrary.enableWriteMyWayDefaults(saved)
        #expect(result.first { $0.label == "Like Me" }?.usesWriteMyWay == true)
        #expect(result.first { $0.label == "Like Me" }?.matchesEnglishLevel == true)
        #expect(result.first { $0.label == "Like Brit." }?.usesWriteMyWay == true)
        #expect(result.first { $0.label == "Email" }?.usesWriteMyWay == false)
        let custom = [Preset(label: "My thing", category: "Write", prompt: "x")]
        #expect(PresetLibrary.enableWriteMyWayDefaults(custom) == custom)
    }

    @Test func newBlurbsAndTonesReplaceTheOldOnesUnlessEdited() throws {
        var saved = PresetLibrary.defaultPresets
        let i = saved.firstIndex { $0.label == "Like Brit." }!, j = saved.firstIndex { $0.label == "Like Me" }!
        saved[i].blurb = "Clear, native English level"; saved[i].tone = "Neutral"
        saved[j].blurb = "My own words"; saved[j].tone = "Personal"
        let result = PresetLibrary.upgradeBuiltIns(saved)
        #expect(result[i].blurb == "Casual Teams message, native English" && result[i].tone == "Casual")
        #expect(result[j].blurb == "My own words" && result[j].tone == "Casual")
    }
}
