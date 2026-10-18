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

    /// The built-in Translate no longer uses the token, but a preset that does (an older
    /// saved one, or a user's own) must still be resolved.
    @Test func aPresetWithTheMotherLanguageTokenIsResolved() {
        let custom = Preset(label: "Translate", category: "Understand", blurb: "Into {{motherLanguage}}",
                            prompt: "Translate this into {{motherLanguage}}", requiresMotherLanguage: true)
        #expect(PromptBuilder.resolvedPrompt(custom, motherLanguage: " Vietnamese ") == "Translate this into Vietnamese")
        #expect(PromptBuilder.resolvedBlurb(custom, motherLanguage: "Vietnamese") == "Into Vietnamese")
        #expect(PromptBuilder.resolvedBlurb(custom, motherLanguage: "  ") == "Into your language from Settings")
    }

    @Test func nonTranslatePromptsAreUntouched() throws {
        let fix = try #require(PresetLibrary.defaultPresets.first { $0.label == "Like Me" })
        #expect(PromptBuilder.resolvedPrompt(fix, motherLanguage: "Vietnamese") == fix.prompt)
        #expect(PromptBuilder.resolvedBlurb(fix, motherLanguage: "Vietnamese") == fix.blurb)
    }

    @Test func finalPromptAppendsIntentOnlyWhenTheTabTakesIt() throws {
        let fix = try #require(PresetLibrary.defaultPresets.first { $0.label == "Like Me" })
        let withIntent = PromptBuilder.finalPrompt(preset: fix, motherLanguage: "", intent: "  say no politely ", tabTakesIntent: true)
        #expect(withIntent == fix.prompt + " say no politely")
        #expect(PromptBuilder.finalPrompt(preset: fix, motherLanguage: "", intent: "ignored", tabTakesIntent: false) == fix.prompt)
        #expect(PromptBuilder.finalPrompt(preset: fix, motherLanguage: "", intent: "   ", tabTakesIntent: true) == fix.prompt)
    }
}

@Suite("Built-in prompts and templates")
struct BuiltInPromptTests {
    private func preset(_ label: String) throws -> Preset {
        try #require(PresetLibrary.defaultPresets.first { $0.label == label })
    }

    @Test func emailPromptIsATemplateStartingWithTheExpertWriterLine() throws {
        let prompt = try preset("Email").prompt
        #expect(prompt.hasPrefix("You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a direct tone. Don't ever use \"—\" in the output.\n\nYou will be given:"))
        #expect(prompt.hasSuffix("REPLY INTENT:\n{reply_intent}"))
        #expect(prompt.contains("ORIGINAL MESSAGE:\n{original_message}"))
        #expect(prompt.contains("8. Output only the reply text."))
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

    @Test func emailIsFilledInLikeMessageAndNotSentInTheOldEmailLayout() throws {
        let email = try preset("Email")
        let prompt = PromptBuilder.finalPrompt(preset: email, motherLanguage: "", intent: "decline politely", tabTakesIntent: true)
        #expect(prompt.hasSuffix("REPLY INTENT:\ndecline politely"))
        let request = PromptBuilder.buildRequest(text: "Can you join?", prompt: prompt, isEmail: email.isEmail)
        #expect(request.content.contains("ORIGINAL MESSAGE:\nCan you join?"))
        #expect(!request.content.contains("Email to reply to:"))
        #expect(!request.content.contains("{original_message}"))
        // The template carries its own rules (greeting, length, no preamble), so the
        // older "start with a greeting, end with a sign-off" system prompt must not apply.
        #expect(!request.system.contains("sign-off"))
    }

    @Test func aPromptWithoutSlotsStillUsesTheEmailLayoutWhenFlaggedAsEmail() {
        let request = PromptBuilder.buildRequest(text: "Can you join?", prompt: "Reply briefly.", isEmail: true)
        #expect(request.system.contains("email writing assistant"))
        #expect(request.content.hasPrefix("Email to reply to:\nCan you join?"))
    }
}

@Suite("Understand defaults and Ask")
struct UnderstandAndAskTests {
    private func preset(_ label: String) throws -> Preset {
        try #require(PresetLibrary.defaultPresets.first { $0.label == label })
    }

    @Test func explainAndTranslateHaveTheNewPrompts() throws {
        #expect(try preset("Explain").prompt == "Explain this in simple terms. Don't ever use \"—\" in the output.")
        let translate = try preset("Translate")
        #expect(translate.prompt == "Translate this into Vietnamese. Don't ever use \"—\" in the output.")
        #expect(!translate.requiresMotherLanguage)           // nothing to fill in, so Send isn't blocked
        #expect(translate.blurb == "Into Vietnamese")
        #expect(PromptBuilder.finalPrompt(preset: translate, motherLanguage: "", intent: nil, tabTakesIntent: false) == translate.prompt)
    }

    @Test func oldCopiesAreUpgradedAndTheMotherLanguageRequirementDropped() throws {
        var saved = PresetLibrary.defaultPresets
        let e = saved.firstIndex { $0.label == "Explain" }!, t = saved.firstIndex { $0.label == "Translate" }!
        saved[e].prompt = "Explain this in simple terms."; saved[e].originalPrompt = "Explain this in simple terms."
        saved[t].prompt = "Translate this into {{motherLanguage}}"; saved[t].originalPrompt = "Translate this into {{motherLanguage}}"
        saved[t].blurb = "Into {{motherLanguage}}"; saved[t].requiresMotherLanguage = true; saved[t].uses = 4
        let result = PresetLibrary.upgradeBuiltIns(saved)
        #expect(result[e].prompt == PresetLibrary.explainPrompt)
        let translate = result[t]
        #expect(translate.prompt == PresetLibrary.translatePrompt)
        #expect(translate.originalPrompt == PresetLibrary.translatePrompt)
        #expect(translate.requiresMotherLanguage == false)
        #expect(translate.blurb == "Into Vietnamese")
        #expect(translate.uses == 4)
    }

    @Test func aTranslatePromptTheUserEditedKeepsItsMotherLanguageBehaviour() throws {
        var saved = PresetLibrary.defaultPresets
        let t = saved.firstIndex { $0.label == "Translate" }!
        saved[t].prompt = "Translate into {{motherLanguage}} and keep the tone."
        saved[t].originalPrompt = "Translate this into {{motherLanguage}}"
        saved[t].requiresMotherLanguage = true
        let translate = PresetLibrary.upgradeBuiltIns(saved)[t]
        #expect(translate.prompt == "Translate into {{motherLanguage}} and keep the tone.")
        #expect(translate.requiresMotherLanguage)
        #expect(translate.originalPrompt == PresetLibrary.translatePrompt)
    }

    // MARK: Ask

    @Test func askSendsThePromptThenTheTextWithNoPresetWording() {
        let both = PromptBuilder.buildAskRequest(prompt: "  Summarise in 3 bullets  ", input: "Long text here.\n")
        #expect(both.content == "Summarise in 3 bullets\n\nLong text here.")
        #expect(both.system.contains("helpful assistant"))
        #expect(!both.content.contains("Text:"))
        #expect(!both.system.contains("text processing assistant"))
    }

    @Test func askWorksWithOnlyAPromptOrOnlyText() {
        #expect(PromptBuilder.buildAskRequest(prompt: "What is a monad?", input: "").content == "What is a monad?")
        #expect(PromptBuilder.buildAskRequest(prompt: "   ", input: "What is a monad?").content == "What is a monad?")
        #expect(PromptBuilder.buildAskRequest(prompt: "", input: "").content == "")
    }

    @Test func askIsNotInTheDefaultTabsOrPresets() {
        #expect(!PresetLibrary.defaultModes.contains("Ask"))
        #expect(!PresetLibrary.defaultPresets.contains { $0.label == "Ask" })
        #expect(PromptBuilder.askTabID != "Ask")      // can't collide with a tab the user names "Ask"
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
