import Foundation
import Testing
@testable import PerMyLastCore

@Suite("PromptBuilder")
struct PromptBuilderTests {
    @Test func emailRequestUsesEmailSystemPrompt() {
        let r = PromptBuilder.buildRequest(text: "Hi there", prompt: "Reply to this email. Additional context: be firm", isEmail: true)
        #expect(r.system.contains("email writing assistant"))
        #expect(r.content.contains("Email to reply to:\nHi there"))
        #expect(r.content.contains("Instructions: Reply to this email. Additional context: be firm"))
    }

    @Test func textRequestUsesTextProcessingSystemPrompt() {
        let r = PromptBuilder.buildRequest(text: "Hi there", prompt: "Make this more professional:", isEmail: false)
        #expect(r.system.contains("text processing assistant"))
        #expect(r.content == "Make this more professional:\n\nText: Hi there")
    }

    @Test func translateResolvesMotherLanguage() throws {
        let translate = try #require(PresetLibrary.defaultPresets.first { $0.label == "Translate" })
        #expect(PromptBuilder.resolvedPrompt(translate, motherLanguage: " Vietnamese ") == "Translate this into Vietnamese")
        #expect(PromptBuilder.resolvedBlurb(translate, motherLanguage: "Vietnamese") == "Into Vietnamese")
        #expect(PromptBuilder.resolvedBlurb(translate, motherLanguage: "  ") == "Into your language from Settings")
    }

    @Test func nonTranslatePromptsAreUntouched() throws {
        let fix = try #require(PresetLibrary.defaultPresets.first { $0.label == "Fix Grammar" })
        #expect(PromptBuilder.resolvedPrompt(fix, motherLanguage: "Vietnamese") == fix.prompt)
        #expect(PromptBuilder.resolvedBlurb(fix, motherLanguage: "Vietnamese") == fix.blurb)
    }

    @Test func finalPromptAppendsIntentOnlyWhenTheTabTakesIt() throws {
        let email = try #require(PresetLibrary.defaultPresets.first { $0.label == "Email" })
        let withIntent = PromptBuilder.finalPrompt(preset: email, motherLanguage: "", intent: "  say no politely ", tabTakesIntent: true)
        #expect(withIntent == email.prompt + " say no politely")
        #expect(PromptBuilder.finalPrompt(preset: email, motherLanguage: "", intent: "ignored", tabTakesIntent: false) == email.prompt)
        #expect(PromptBuilder.finalPrompt(preset: email, motherLanguage: "", intent: "   ", tabTakesIntent: true) == email.prompt)
    }
}

@Suite("Languages / WartimePeacetime")
struct ReferenceDataTests {
    @Test func languagesAreSortedAndSearchable() {
        let names = Languages.all.map(\.name)
        #expect(names == names.sorted())
        #expect(Languages.find("ese").map(\.name).contains("Vietnamese"))
        #expect(Languages.find("   ").isEmpty)
        #expect(Languages.find("ese", limit: 2).count == 2)
    }

    @Test func exportTextNamesTheModeAndIncludesContext() {
        let text = WartimePeacetime.exportText(for: .wartime)
        #expect(text.hasPrefix("COMPANY OPERATING MODE: WARTIME"))
        #expect(text.contains("Business pressure"))
        #expect(text.contains("Context: Wartime works when"))
        #expect(WartimePeacetime.exportText(for: .peacetime).hasPrefix("COMPANY OPERATING MODE: PEACETIME"))
    }
}
