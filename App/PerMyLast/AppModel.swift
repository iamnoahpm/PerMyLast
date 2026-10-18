import AppKit
import Observation
import PerMyLastCore

/// Everything the popup and settings windows show or change.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Settings (persisted)
    var settings: AppSettings
    var apiKey = ""
    /// False until the Keychain read finishes (it can block on a system dialog,
    /// so it never runs on the main thread during launch).
    var apiKeyLoaded = false
    var modes: [String]
    var presets: [Preset]
    var intentModes: [String]

    // MARK: Session (not persisted)
    var enabled = true
    var hotKeyError: String?
    var activeMode: String
    var selectedLabel: String?
    var inputText = ""
    var intent = ""
    var output = ""
    var errorMessage: String?
    var isSending = false
    var hasResult = false
    /// Bumped each time the popup opens so the text box can grab focus.
    var focusToken = 0

    private let client = AnthropicClient()
    private let apiKeyAccount = "anthropic-api-key"

    private init() {
        let modes = Persistence.load("modes", as: [String].self) ?? PresetLibrary.defaultModes
        let loaded = Persistence.load("presets", as: [Preset].self) ?? PresetLibrary.defaultPresets
        self.modes = modes
        self.presets = PresetLibrary.normalize(loaded, modes: modes)
        self.intentModes = Persistence.load("intentModes", as: [String].self) ?? ["Reply"]
        self.settings = Persistence.load("settings", as: AppSettings.self) ?? AppSettings()
        self.activeMode = modes.first ?? PresetLibrary.defaultModes[0]
        self.selectedLabel = nil
        selectDefaultPreset()
    }

    // MARK: Persistence

    func saveSettings() { Persistence.save(settings, key: "settings") }
    private var savedAPIKey = ""

    /// Reads the key from the Keychain off the main thread.
    func loadAPIKey() async {
        let account = apiKeyAccount
        let stored = await Task.detached(priority: .userInitiated) { KeychainStore.read(account: account) ?? "" }.value
        savedAPIKey = stored
        if apiKey.isEmpty { apiKey = stored }
        apiKeyLoaded = true
    }

    /// Writes the key to the Keychain, skipping no-op saves (including the one
    /// triggered by `loadAPIKey` filling the field).
    func saveAPIKey() {
        guard apiKeyLoaded else { return }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != savedAPIKey else { return }
        savedAPIKey = trimmed
        let account = apiKeyAccount
        Task.detached(priority: .userInitiated) { KeychainStore.write(trimmed, account: account) }
    }

    // MARK: Presets

    var presetsInActiveMode: [Preset] {
        presets.filter { PresetLibrary.normalizeCategory($0.category, modes: modes) == activeMode }
    }

    var currentPreset: Preset? {
        presetsInActiveMode.first { $0.label == selectedLabel }
    }

    var activeModeTakesIntent: Bool { intentModes.contains(activeMode) }

    func selectDefaultPreset() {
        let inMode = presetsInActiveMode
        selectedLabel = (inMode.first(where: \.isDefault) ?? inMode.first)?.label
    }

    func blurb(for preset: Preset) -> String {
        PromptBuilder.resolvedBlurb(preset, motherLanguage: settings.motherLanguage)
    }

    // MARK: Hotkey

    /// The hotkey opens the popup with whatever is on the clipboard (the user
    /// presses ⌘C first). Nothing on the clipboard means nothing happens.
    func handleHotKey() {
        guard enabled else { return }
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        inputText = text
        output = ""
        errorMessage = nil
        hasResult = false
        WindowCoordinator.shared.showPopup()
        focusToken += 1
    }

    // MARK: Sending

    func send() async {
        guard let preset = currentPreset, !isSending else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { errorMessage = "Select or paste text first."; return }
        if preset.requiresMotherLanguage,
           settings.motherLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Set your mother language in Settings to use \(preset.label)."
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let prompt = PromptBuilder.finalPrompt(
            preset: preset, motherLanguage: settings.motherLanguage,
            intent: intent, tabTakesIntent: activeModeTakesIntent)
        let config = AnthropicConfig(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: settings.model, effort: settings.effort,
            workspaceId: settings.workspaceId.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            output = try await client.process(config: config, text: text, prompt: prompt, isEmail: preset.isEmail)
            hasResult = true
            presets = PresetLibrary.incrementUses(presets, label: preset.label)
            Persistence.save(presets, key: "presets")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }
}
