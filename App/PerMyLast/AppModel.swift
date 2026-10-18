import AppKit
import Observation
import SwiftUI
import PerMyLastCore

/// Everything the popup and settings windows show or change.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    static let feedbackEmail = "iamnoahpm@gmail.com"

    // MARK: Settings (persisted)
    var settings: AppSettings
    var apiKey = ""
    /// False until the Keychain read finishes (it can block on a system dialog,
    /// so it never runs on the main thread during launch).
    var apiKeyLoaded = false
    var modes: [String]
    var presets: [Preset]
    var intentModes: [String]
    private(set) var enabled: Bool

    // MARK: Session (not persisted)
    var hotKeyError: String?
    var shortcutBannerDismissed = false
    /// Bumped by the Settings footer to jump to the feedback box.
    var feedbackFocusToken = 0
    /// Briefly true after a settings change was saved (drives the "Saved" flash).
    var settingsSavedFlash = false
    var writeMyWay: WriteMyWaySettings
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

    // Prompt panel
    var promptOpen = false
    var editingPrompt = false
    var promptDraft = ""
    var savedFlash: String?
    private var flashTask: Task<Void, Never>?

    private let client = AnthropicClient()
    private let apiKeyAccount = "anthropic-api-key"
    private var savedAPIKey = ""

    private init() {
        let modes = Persistence.load("modes", as: [String].self) ?? PresetLibrary.defaultModes
        let loaded = Persistence.load("presets", as: [Preset].self) ?? PresetLibrary.defaultPresets
        self.modes = modes
        self.presets = PresetLibrary.normalize(loaded, modes: modes)
        self.intentModes = Persistence.load("intentModes", as: [String].self) ?? (modes.contains("Reply") ? ["Reply"] : [])
        self.settings = Persistence.load("settings", as: AppSettings.self) ?? AppSettings()
        self.enabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        self.writeMyWay = Persistence.load("writeMyWay", as: WriteMyWaySettings.self) ?? WriteMyWaySettings()
        self.activeMode = modes.first ?? PresetLibrary.defaultModes[0]
        self.selectedLabel = nil
        selectDefaultPreset()
    }

    // MARK: Persistence

    func saveSettings() {
        Persistence.save(settings, key: "settings")
        applyDockVisibility()
        if HotKeyCenter.shared.registered != settings.shortcut { applyShortcut() }
        flashSaved()
    }

    func saveWriteMyWay() { Persistence.save(writeMyWay, key: "writeMyWay") }

    private var savedFlashTask: Task<Void, Never>?
    func flashSaved() {
        settingsSavedFlash = true
        savedFlashTask?.cancel()
        savedFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.settingsSavedFlash = false }
        }
    }

    // MARK: Shortcut

    /// Registers the saved shortcut; reports a clash with another app.
    func applyShortcut() {
        let ok = HotKeyCenter.shared.apply(accelerator: settings.shortcut)
        hotKeyError = ok ? nil : L("\(shortcutDisplay) is already used by another app.")
    }

    var shortcutDisplay: String {
        KeyCombo(accelerator: settings.shortcut)?.display ?? ShortcutConflicts.display(settings.shortcut)
    }

    /// An advisory (app-level) clash for the saved shortcut, shown as a banner.
    var shortcutAppConflict: ShortcutConflict? {
        ShortcutConflicts.find(settings.shortcut, scope: .app)
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "isEnabled")
    }

    func setShowInDock(_ value: Bool) {
        settings.showInDock = value
        saveSettings()
    }

    /// Dock icon on (regular app) or off (menu bar only).
    func applyDockVisibility() {
        let policy: NSApplication.ActivationPolicy = settings.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    /// Reads the key from the Keychain off the main thread.
    func loadAPIKey() async {
        let account = apiKeyAccount
        let stored = await Task.detached(priority: .userInitiated) { KeychainStore.read(account: account) ?? "" }.value
        savedAPIKey = stored
        if apiKey.isEmpty { apiKey = stored }
        apiKeyLoaded = true
    }

    private var apiKeyWriteTask: Task<Void, Never>?

    /// Writes the key to the Keychain shortly after typing stops. Skips no-op
    /// saves (including the one `loadAPIKey` triggers by filling the field) and
    /// anything that isn't an Anthropic key, as the Electron app did.
    func saveAPIKey() {
        guard apiKeyLoaded else { return }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != savedAPIKey, trimmed.isEmpty || trimmed.hasPrefix("sk-ant-") else { return }
        apiKeyWriteTask?.cancel()
        apiKeyWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled, let self else { return }
            savedAPIKey = trimmed
            let account = apiKeyAccount
            await Task.detached(priority: .userInitiated) { KeychainStore.write(trimmed, account: account) }.value
            flashSaved()
        }
    }

    var apiKeyLooksInvalid: Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("sk-ant-")
    }

    private func savePresets() { Persistence.save(presets, key: "presets") }

    // MARK: Presets

    var presetsInActiveMode: [Preset] {
        presets.filter { PresetLibrary.normalizeCategory($0.category, modes: modes) == activeMode }
    }

    var currentPreset: Preset? {
        presetsInActiveMode.first { $0.label == selectedLabel }
    }

    var activeModeTakesIntent: Bool { intentModes.contains(activeMode) }

    var motherLanguageMissing: Bool {
        guard let preset = currentPreset, preset.requiresMotherLanguage else { return false }
        return settings.motherLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSend: Bool {
        !isSending && currentPreset != nil && !motherLanguageMissing
            && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func selectDefaultPreset() {
        let inMode = presetsInActiveMode
        selectedLabel = (inMode.first(where: \.isDefault) ?? inMode.first)?.label
        editingPrompt = false
        savedFlash = nil
    }

    func select(_ preset: Preset) {
        selectedLabel = preset.label
        editingPrompt = false
        savedFlash = nil
    }

    /// Arrow-key navigation along the chips.
    func selectNeighbour(_ step: Int) {
        let inMode = presetsInActiveMode
        guard !inMode.isEmpty else { return }
        let current = inMode.firstIndex { $0.label == selectedLabel } ?? 0
        select(inMode[(current + step + inMode.count) % inMode.count])
    }

    func blurb(for preset: Preset) -> String {
        PromptBuilder.resolvedBlurb(preset, motherLanguage: settings.motherLanguage)
    }

    func resolvedPrompt(for preset: Preset) -> String {
        PromptBuilder.resolvedPrompt(preset, motherLanguage: settings.motherLanguage)
    }

    func isEdited(_ preset: Preset) -> Bool { preset.prompt != preset.originalPrompt }

    func savedTargetLabel(_ preset: Preset) -> String { "\(preset.category) › \(preset.label)" }

    // MARK: Prompt panel

    func togglePrompt() {
        promptOpen.toggle()
        editingPrompt = false
    }

    func openPromptEditor() {
        guard let preset = currentPreset else { return }
        promptOpen = true
        editingPrompt = true
        promptDraft = preset.prompt
        savedFlash = nil
    }

    func cancelPromptEdit() { editingPrompt = false }

    func revertPromptDraft() {
        if let preset = currentPreset { promptDraft = preset.originalPrompt }
    }

    /// Saves the edited prompt back into the preset. An empty draft, or one
    /// equal to the original, restores the original.
    func savePromptEdit() {
        guard let preset = currentPreset else { return }
        let draft = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (draft.isEmpty || draft == preset.originalPrompt) ? preset.originalPrompt : draft
        presets = PresetLibrary.upsert(presets, draft: PresetDraft(
            label: preset.label, category: preset.category, icon: preset.icon, blurb: preset.blurb,
            tone: preset.tone, prompt: next, isEmail: preset.isEmail, isDefault: preset.isDefault,
            requiresMotherLanguage: preset.requiresMotherLanguage), modes: modes)
        savePresets()
        editingPrompt = false
        flash(L("Saved to \(savedTargetLabel(preset))"))
    }

    private func flash(_ message: String) {
        savedFlash = message
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            if !Task.isCancelled { self?.savedFlash = nil }
        }
    }

    // MARK: Tabs and preset editing (Settings → Tone Presets)

    private func saveModes() {
        Persistence.save(modes, key: "modes")
        Persistence.save(intentModes, key: "intentModes")
    }

    /// Keeps the popup valid after presets or tabs changed underneath it.
    private func presetsDidChange() {
        if !modes.contains(activeMode) { activeMode = modes.first ?? PresetLibrary.defaultModes[0] }
        if currentPreset == nil { selectDefaultPreset() }
    }

    func addMode() {
        modes = PresetLibrary.addMode(modes)
        saveModes()
    }

    @discardableResult
    func renameMode(from: String, to: String) -> Bool {
        guard let result = PresetLibrary.renameMode(modes, presets: presets, from: from, to: to) else { return false }
        let newName = to.trimmingCharacters(in: .whitespacesAndNewlines)
        modes = result.modes
        presets = result.presets
        intentModes = intentModes.map { $0 == from ? newName : $0 }
        if activeMode == from { activeMode = newName }
        saveModes(); savePresets()
        presetsDidChange()
        return true
    }

    @discardableResult
    func deleteMode(_ name: String) -> Bool {
        guard let result = PresetLibrary.deleteMode(modes, presets: presets, name: name) else { return false }
        modes = result.modes
        presets = result.presets
        intentModes.removeAll { $0 == name }
        saveModes(); savePresets()
        presetsDidChange()
        return true
    }

    func moveModes(from: IndexSet, to: Int) {
        var reordered = modes
        reordered.move(fromOffsets: from, toOffset: to)
        modes = PresetLibrary.reorderModes(modes, ordered: reordered)
        saveModes()
    }

    /// Applies the Settings editor's rows (reorder, rename, edits, default flag).
    func applyPresetEdits(_ edits: [PresetEdit]) {
        presets = PresetLibrary.applyEdits(stored: presets, incoming: edits, modes: modes)
        savePresets()
        presetsDidChange()
    }

    /// Adds a uniquely named, empty action to a tab and returns its label.
    @discardableResult
    func addPreset(to mode: String) -> String {
        let existing = Set(presets.filter { PresetLibrary.normalizeCategory($0.category, modes: modes) == mode }.map(\.label))
        var label = "New Action"
        var n = 2
        while existing.contains(label) { label = "New Action \(n)"; n += 1 }
        presets = PresetLibrary.upsert(presets, draft: PresetDraft(label: label, category: mode, prompt: ""), modes: modes)
        savePresets()
        presetsDidChange()
        return label
    }

    func deletePreset(_ label: String) {
        presets = PresetLibrary.delete(presets, label: label, modes: modes)
        savePresets()
        presetsDidChange()
    }

    // MARK: Hotkey

    /// The hotkey opens the popup with whatever is on the clipboard (the user
    /// presses ⌘C first). Nothing on the clipboard means nothing happens.
    func handleHotKey() {
        guard enabled else { return }
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        inputText = TextCleanup.beautify(text)
        output = ""
        errorMessage = nil
        hasResult = false
        shortcutBannerDismissed = false
        WindowCoordinator.shared.showPopup()
        focusToken += 1
    }

    // MARK: Sending

    func send() async {
        guard let preset = currentPreset, !isSending else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { errorMessage = L("Select or paste text first"); return }
        if motherLanguageMissing {
            errorMessage = L("Set your mother language in Settings first")
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
            let result = try await client.process(config: config, text: text, prompt: prompt, isEmail: preset.isEmail)
            output = TextCleanup.beautify(result)
            hasResult = true
            presets = PresetLibrary.incrementUses(presets, label: preset.label)
            savePresets()
        } catch {
            hasResult = false
            errorMessage = error.localizedDescription
        }
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    // MARK: Footer actions

    func sendFeedback(body: String = "") {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.feedbackEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Per My Last Feedback"),
                                 URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = L("You're on version \(appVersion)")
        alert.informativeText = L("Automatic update checking isn't set up yet. For now, download new builds from wherever you got this one.")
        alert.runModal()
    }

    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
}
