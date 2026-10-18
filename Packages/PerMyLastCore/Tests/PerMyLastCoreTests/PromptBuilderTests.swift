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

@Suite("Built-in prompts and templates")
struct BuiltInPromptTests {
    private func preset(_ label: String) throws -> Preset {
        try #require(PresetLibrary.defaultPresets.first { $0.label == label })
    }

    @Test func emailPromptIsTheNewWording() throws {
        #expect(try preset("Email").prompt == "You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a direct tone. Don't ever use \"—\" in the output.")
    }

    @Test func messagePromptIsATemplateWithBothSlots() throws {
        let prompt = try preset("Message").prompt
        #expect(prompt.hasPrefix("You are drafting a reply to a message on the user's behalf."))
        #expect(prompt.hasSuffix("REPLY INTENT:\n{reply_intent}"))
        #expect(prompt.contains("ORIGINAL MESSAGE:\n{original_message}"))
        #expect(prompt.contains("7. Never use an em dash (\"—\") anywhere in the output."))
    }

    @Test func templateGetsTheIntentAndTheMessageSubstituted() throws {
        let message = try preset("Message")
        let prompt = PromptBuilder.finalPrompt(preset: message, motherLanguage: "", intent: "  maybe, let me check  ", tabTakesIntent: true)
        #expect(prompt.contains("REPLY INTENT:\nmaybe, let me check"))
        #expect(prompt.contains("{original_message}"))          // filled in when the request is built
        #expect(!prompt.contains("{reply_intent}"))

        let request = PromptBuilder.buildRequest(text: "Hey Noah, can you make 3pm?", prompt: prompt, isEmail: message.isEmail)
        #expect(request.content.contains("ORIGINAL MESSAGE:\nHey Noah, can you make 3pm?"))
        #expect(!request.content.contains("{original_message}"))
        #expect(!request.content.contains("Text:"))              // not the plain "prompt + Text:" layout
        #expect(request.system.contains("text processing assistant"))
    }

    @Test func templateWithoutAnIntentSaysSoInsteadOfLeavingItBlank() throws {
        let message = try preset("Message")
        let prompt = PromptBuilder.finalPrompt(preset: message, motherLanguage: "", intent: "   ", tabTakesIntent: true)
        #expect(prompt.contains("REPLY INTENT:\n(none given"))
        // A stale intent from another tab must not leak in.
        let stale = PromptBuilder.finalPrompt(preset: message, motherLanguage: "", intent: "old text", tabTakesIntent: false)
        #expect(!stale.contains("old text"))
    }

    @Test func emailKeepsTheEmailLayoutAndAppendsTheIntent() throws {
        let email = try preset("Email")
        let prompt = PromptBuilder.finalPrompt(preset: email, motherLanguage: "", intent: "decline politely", tabTakesIntent: true)
        #expect(prompt.hasSuffix("in the output. decline politely"))
        let request = PromptBuilder.buildRequest(text: "Can you join?", prompt: prompt, isEmail: true)
        #expect(request.system.contains("email writing assistant"))
        #expect(request.content.hasPrefix("Email to reply to:\nCan you join?"))
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
