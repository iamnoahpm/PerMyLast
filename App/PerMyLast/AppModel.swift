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
    var apiKey: String
    var modes: [String]
    var presets: [Preset]
    var intentModes: [String]
    private(set) var enabled: Bool

    // MARK: Session (not persisted)
    var hotKeyError: String?
    var shortcutBannerDismissed = false
    /// Briefly true after a settings change was saved (drives the "Saved" flash).
    var settingsSavedFlash = false
    var writeMyWay: WriteMyWaySettings
    var activeMode: String
    var selectedLabel: String?
    var inputText = ""
    var intent = ""
    /// Screenshots of the message being answered, and of what the user wants to say (Reply).
    var theirImages: [AttachedImage] = []
    var intentImages: [AttachedImage] = []
    /// The Ask tab's free-form prompt (that tab has no preset behind it).
    var askPrompt = ""
    var output = ""
    var errorMessage: String?
    var isSending = false
    var hasResult = false
    /// Set when the last run failed with a backend error, so the error box can offer the right next step.
    var lastErrorKind: BackendError.Kind?
    /// Bumped each time the popup opens so the text box can grab focus.
    var focusToken = 0

    // Prompt panel
    var promptOpen = false
    var editingPrompt = false
    var promptDraft = ""
    var savedFlash: String?
    private var flashTask: Task<Void, Never>?

    /// The user's own Anthropic key lives in the Keychain. Earlier builds kept it
    /// in app preferences under `legacyAPIKeyDefaultsKey`; it is moved on first launch.
    private let keyStore: any APIKeyStore = KeychainAPIKeyStore()
    private static let legacyAPIKeyDefaultsKey = "anthropicAPIKey"
    private var keySaveTask: Task<Void, Never>?

    /// Result of the last "Test key" (FR-A11). Any edit to the key resets it.
    enum KeyStatus: Equatable { case untested, testing, valid, invalid(String) }
    var keyStatus = KeyStatus.untested
    /// Set when the Keychain refused to read or write the key.
    var keyStoreError: String?

    private init() {
        let modes = Persistence.load("modes", as: [String].self) ?? PresetLibrary.defaultModes
        let loaded = Persistence.load("presets", as: [Preset].self) ?? PresetLibrary.defaultPresets
        var upgraded = PresetLibrary.upgradeBuiltIns(loaded)
        // Presets saved before Write My Way was connected: switch it on for the built-in rewrite actions, once.
        if UserDefaults.standard.integer(forKey: "presetSchemaVersion") < 1 {
            upgraded = PresetLibrary.enableWriteMyWayDefaults(upgraded)
            UserDefaults.standard.set(1, forKey: "presetSchemaVersion")
        }
        self.modes = modes
        let normalized = PresetLibrary.normalize(upgraded, modes: modes)
        self.presets = normalized
        if upgraded != loaded { Persistence.save(normalized, key: "presets") }
        self.intentModes = Persistence.load("intentModes", as: [String].self) ?? (modes.contains("Reply") ? ["Reply"] : [])
        self.settings = Persistence.load("settings", as: AppSettings.self) ?? AppSettings()
        let migrated = APIKeyMigration.migrate(
            legacy: UserDefaults.standard.string(forKey: Self.legacyAPIKeyDefaultsKey), store: keyStore,
            clearLegacy: { UserDefaults.standard.removeObject(forKey: Self.legacyAPIKeyDefaultsKey) })
        self.apiKey = migrated.key
        self.keyStoreError = migrated.error.map { L("Couldn't reach the Keychain: \($0.localizedDescription)") }
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
        StatusItemController.shared.refreshIcon()
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

    /// Saves the key shortly after it's typed. Skips anything that isn't an
    /// Anthropic key (the field can still show it, flagged), as the Electron app did.
    func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        keyStatus = .untested
        guard trimmed.isEmpty || trimmed.hasPrefix("sk-ant-") else { return }
        keySaveTask?.cancel()
        keySaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { self?.persistAPIKey(trimmed) }
        }
    }

    /// Writes the key to the Keychain now (empty removes it).
    private func persistAPIKey(_ key: String) {
        keySaveTask?.cancel()
        do {
            if key.isEmpty { try keyStore.delete() } else { try keyStore.save(key) }
            keyStoreError = nil
            flashSaved()
        } catch {
            keyStoreError = L("Couldn't save the key to the Keychain: \(error.localizedDescription)")
        }
    }

    func removeAPIKey() {
        apiKey = ""
        keyStatus = .untested
        persistAPIKey("")
    }

    /// "Test key": a one-token request to Anthropic (FR-A11).
    func testAPIKey() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !apiKeyLooksInvalid, keyStatus != .testing else { return }
        persistAPIKey(key)
        keyStatus = .testing
        do {
            try await AnthropicClient().testKey(
                apiKey: key, workspaceId: settings.workspaceId.trimmingCharacters(in: .whitespacesAndNewlines))
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == key { keyStatus = .valid }
        } catch {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == key { keyStatus = .invalid(error.localizedDescription) }
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

    static let askTab = PromptBuilder.askTabID

    /// The Ask tab is on: a plain prompt box instead of preset actions.
    var isAsk: Bool { activeMode == Self.askTab }

    var motherLanguageMissing: Bool {
        guard let preset = currentPreset, preset.requiresMotherLanguage else { return false }
        return settings.motherLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSend: Bool {
        if isAsk {
            return !isSending && !askPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !isSending, currentPreset != nil, !motherLanguageMissing else { return false }
        if activeModeTakesIntent {
            // Reply: their text, an intent, or a screenshot is enough.
            return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !theirImages.isEmpty || !intentImages.isEmpty
        }
        return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !theirImages.isEmpty
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

    /// True when the user's Write My Way choices will be added to this action's prompt.
    func writeMyWayApplies(to preset: Preset) -> Bool {
        PromptBuilder.appliesWriteMyWay(preset, writeMyWay)
    }

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
            requiresMotherLanguage: preset.requiresMotherLanguage,
            usesWriteMyWay: preset.usesWriteMyWay, matchesEnglishLevel: preset.matchesEnglishLevel), modes: modes)
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
    func presetsDidChange() {
        if !isAsk, !modes.contains(activeMode) { activeMode = modes.first ?? PresetLibrary.defaultModes[0] }
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

    /// Applies one action's edit (everything else unchanged). Used by the live editor.
    func updatePreset(originalLabel: String, edit: PresetEdit) {
        let incoming = presets.map { p -> PresetEdit in
            if p.label == originalLabel { return edit }
            return PresetEdit(originalLabel: p.label, label: p.label, icon: p.icon, blurb: p.blurb,
                              tone: p.tone, prompt: p.prompt, isDefault: p.isDefault)
        }
        applyPresetEdits(incoming)
        flashSaved()
    }

    func presetLabelTaken(_ label: String, except original: String) -> Bool {
        label != original && presets.contains { $0.label == label }
    }

    /// Drag-reorder inside one tab; other tabs keep their order.
    func reorderActions(in mode: String, from: IndexSet, to: Int) {
        var inMode = presets.filter { PresetLibrary.normalizeCategory($0.category, modes: modes) == mode }
        inMode.move(fromOffsets: from, toOffset: to)
        var next = inMode.makeIterator()
        presets = presets.map { p in
            PresetLibrary.normalizeCategory(p.category, modes: modes) == mode ? (next.next() ?? p) : p
        }
        savePresets()
        flashSaved()
    }

    /// Makes `label` the action shown first when its tab opens.
    func setDefaultPreset(_ label: String) {
        guard let target = presets.first(where: { $0.label == label }) else { return }
        let category = PresetLibrary.normalizeCategory(target.category, modes: modes)
        presets = presets.map { p in
            var q = p
            if PresetLibrary.normalizeCategory(p.category, modes: modes) == category { q.isDefault = (p.label == label) }
            return q
        }
        savePresets()
        presetsDidChange()
        flashSaved()
    }

    func deletePreset(_ label: String) {
        presets = PresetLibrary.delete(presets, label: label, modes: modes)
        savePresets()
        presetsDidChange()
    }

    // MARK: Hotkey

    /// The hotkey copies the current selection in the frontmost app (a synthetic ⌘C) and opens the popup with it.
    /// macOS only allows that once the user grants Accessibility; without it, or with nothing selected, it uses
    /// whatever is already on the clipboard. The Services entry (see `ServicesProvider`) needs no permission.
    func handleHotKey() {
        guard enabled else { return }
        Task { @MainActor in
            if let selection = await Self.copySelection() {
                open(with: selection, source: .selection)
            } else if let text = NSPasteboard.general.string(forType: .string) {
                open(with: text, source: .clipboard)
            }
        }
    }

    /// Whether macOS lets the app send keystrokes to other apps (needed to copy the selection).
    static var canCopySelection: Bool { CGPreflightPostEventAccess() }

    /// macOS shows its permission prompt only once per app; after that `CGRequestPostEventAccess` is a silent no-op,
    /// so later calls send the user to the Accessibility pane instead.
    static func requestCopyAccess() {
        let key = "didRequestPostEventAccess"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            if CGRequestPostEventAccess() { return }
        } else if CGPreflightPostEventAccess() { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    /// Opens a fresh copy of this app and quits this one. macOS applies a newly granted Accessibility permission
    /// only to processes started after the grant, so this is the step that makes "Allow access" take effect.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Whether the permission prompt has been shown already (so the next step is Settings, then a restart).
    static var didAskForCopyAccess: Bool { UserDefaults.standard.bool(forKey: "didRequestPostEventAccess") }

    /// Sends ⌘C to the frontmost app and returns the text it copied, then puts the user's previous clipboard back.
    /// Nil if permission is missing or nothing was selected.
    private static func copySelection() async -> String? {
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else { return nil }
        let pasteboard = NSPasteboard.general
        // Let go of the hotkey's own modifiers first, or the target app sees ⇧⌘⌥-C instead of ⌘C.
        for _ in 0..<20 where !NSEvent.modifierFlags.intersection([.shift, .option, .control, .command]).isEmpty {
            try? await Task.sleep(for: .milliseconds(25))
        }
        let saved = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        let before = pasteboard.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8 // kVK_ANSI_C
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
        for _ in 0..<24 where pasteboard.changeCount == before {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        return text
    }

    /// Opens the popup with `text` as the input, or as the question in Ask mode.
    func open(with text: String, source: CaptureSource = .service) {
        guard enabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // On the onboarding shortcut step the capture is the test; show it there instead of loading the popup behind it.
        if OnboardingModel.shared.noteCapture(text, source: source) { WindowCoordinator.shared.showPopup(); return }
        if isAsk { askPrompt = TextCleanup.beautify(text) } else { inputText = TextCleanup.beautify(text) }
        theirImages = []
        intentImages = []
        output = ""
        errorMessage = nil
        hasResult = false
        shortcutBannerDismissed = false
        WindowCoordinator.shared.showPopup()
        focusToken += 1
    }

    // MARK: Sending

    private func makeConfig() -> AnthropicConfig {
        AnthropicConfig(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: settings.model, effort: settings.effort,
            workspaceId: settings.workspaceId.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Every AI request goes through `AIClient`: the shared key via the backend for trial and Pro, or the
    /// user's own key straight to Anthropic (FR-A4).
    private func makeClient(forceRefresh: Bool = false) async throws -> (client: any AIClient, viaProxy: Bool) {
        let account = AccountModel.shared
        switch account.route(hasOwnKey: !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
        case .direct:
            // FR-P7: a Lifetime licence covers builds released before its updates ended.
            if case .renewalNeeded(let until) = account.updateWindow, account.entitlement?.plan == .lifetime {
                throw BackendError(code: "updates_expired", message: L("Renew updates to use this version. Your updates ended \(until.formatted(date: .abbreviated, time: .omitted))."))
            }
            return (DirectAnthropicClient(config: makeConfig()), false)
        case .proxy:
            guard let base = AppConfig.backendURL else { throw AnthropicError.missingAPIKey }
            let token = try await account.validAccessToken(forceRefresh: forceRefresh)
            return (ProxyClient(baseURL: base, accessToken: token, model: settings.model, effort: settings.effort, onRunsRemaining: { remaining in
                Task { @MainActor in AccountModel.shared.noteRunsRemaining(remaining) }
            }), true)
        case .keySetup:
            throw AnthropicError.missingAPIKey
        case .paywall:
            throw BackendError(code: "no_entitlement", message: "")
        case .verifyOnline:
            throw BackendError(code: "unreachable", message: L("Connect to the internet to verify your license."))
        case .signIn:
            throw BackendError(code: "unauthenticated", message: L("Sign in in Settings to use your free credits, or add your own API key."))
        }
    }

    /// Runs a template and shows the answer as it streams in.
    private func stream(_ run: TemplateRun, images: [ClaudeImage] = []) async throws {
        output = ""
        hasResult = false
        var text = ""
        for attempt in 0..<2 {
            let (client, viaProxy) = try await makeClient(forceRefresh: attempt == 1)
            do {
                for try await delta in client.run(templateID: run.templateID, variables: run.variables, images: images) {
                    text += delta
                    output = TextCleanup.beautify(text)
                    hasResult = true
                }
                return
            } catch let error as BackendError where viaProxy && attempt == 0 && error.kind == .unauthenticated && text.isEmpty {
                continue   // the token was rejected: refresh it once and try again
            } catch let error as BackendError {
                if viaProxy { Task { await AccountModel.shared.refreshEntitlement() } }
                throw error
            }
        }
    }

    /// A readable message for any failure of a run.
    private func describe(_ error: Error) -> String {
        lastErrorKind = (error as? BackendError)?.kind
        guard let e = error as? BackendError else { return error.localizedDescription }
        switch e.kind {
        case .noEntitlement, .freeCreditsExhausted:
            WindowCoordinator.shared.showPaywall()   // FR-A15
            if let end = AccountModel.shared.entitlement?.periodEnd, e.kind == .freeCreditsExhausted {
                return L("You've used this month's free credits. They renew on \(end.formatted(date: .abbreviated, time: .omitted)). Choose a plan, or use your own Anthropic API key (Settings → General).")
            }
            return L("You've used this month's free credits. Choose a plan, or use your own Anthropic API key (Settings → General).")
        case .quotaExhausted:
            if let end = AccountModel.shared.entitlement?.periodEnd {
                return L("You've used this month's runs. They reset on \(end.formatted(date: .abbreviated, time: .omitted)).")
            }
            return L("You've used this month's runs.")
        case .byokRequired: return L("Your plan uses your own Anthropic API key. Add it in Settings.")
        case .updatesExpired:
            WindowCoordinator.shared.showPaywall()   // it has "Renew updates"
            return e.message
        case .inputTooLarge: return L("That text is too long (limit \(e.limit ?? 0) characters).")
        case .unauthenticated: return e.message.isEmpty ? L("Sign in to continue.") : e.message
        default: return AccountModel.shared.friendly(e)
        }
    }

    func send() async {
        guard !isSending else { return }
        if isAsk { await sendAsk(); return }
        guard let preset = currentPreset else { return }
        let typed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = (theirImages + intentImages).map { ClaudeImage(mediaType: $0.mediaType, data: $0.data) }
        let replyWithoutText = !images.isEmpty
            || (activeModeTakesIntent && !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        guard !typed.isEmpty || replyWithoutText else { errorMessage = L("Select or paste text first"); return }
        let text = typed.isEmpty ? "[from the screenshot]" : typed
        if motherLanguageMissing {
            errorMessage = L("Set your mother language in Settings first")
            return
        }

        isSending = true
        errorMessage = nil
        lastErrorKind = nil
        defer { isSending = false }

        let prompt = PromptBuilder.finalPrompt(
            preset: preset, motherLanguage: settings.motherLanguage,
            intent: intent, tabTakesIntent: activeModeTakesIntent,
            writeMyWay: writeMyWay)
        do {
            var sent = prompt
            if !images.isEmpty {
                sent += "\n\nAttached: \(images.count) screenshot\(images.count == 1 ? "" : "s"). Read the text in \(images.count == 1 ? "it" : "them") as part of the message."
            }
            let run = PromptBuilder.templateRun(text: text, prompt: sent, isEmail: preset.isEmail)
            try await stream(run, images: images)
            OnboardingModel.shared.noteRealRun()
            presets = PresetLibrary.incrementUses(presets, label: preset.label)
            savePresets()
        } catch {
            hasResult = false
            errorMessage = describe(error)
        }
    }

    /// Ask: the user's own question, straight to the model.
    private func sendAsk() async {
        let prompt = askPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            errorMessage = L("Type your question first")
            return
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let images = theirImages.map { ClaudeImage(mediaType: $0.mediaType, data: $0.data) }
            var sent = prompt
            if !images.isEmpty {
                sent += "\n\nAttached: \(images.count) screenshot\(images.count == 1 ? "" : "s"). Read the text in \(images.count == 1 ? "it" : "them") as part of the message."
            }
            try await stream(PromptBuilder.askRun(prompt: sent, input: ""), images: images)
            OnboardingModel.shared.noteRealRun()
        } catch {
            hasResult = false
            errorMessage = describe(error)
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
