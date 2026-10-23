import PerMyLastCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var isStandardModel: Bool {
        ModelCatalog.standardModels.contains { $0.id == model.settings.model }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            AccountSection()
            anthropicSection(model: $model)
            modelSection(model: $model)
            Section { ShortcutRecorderRow() }
            languageSection(model: $model)
            generalSection(model: $model)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(PMLColor.surfaceInset)
        .tint(PMLColor.accent)
        .font(PMLFont.body)
    }

    // MARK: Sections

    private func anthropicSection(model: Bindable<AppModel>) -> some View {
        Section("Claude API Key") {
            SecureField("Claude API Key", text: model.apiKey, prompt: Text("sk-ant-…"))
                .onChange(of: self.model.apiKey) { self.model.saveAPIKey() }
            HStack(spacing: 4) {
                Text("Get one at")
                Link("console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
            }
            .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            if self.model.apiKeyLooksInvalid {
                Text("API key must start with \"sk-ant-\"").font(PMLFont.hint).foregroundStyle(PMLColor.danger)
            }
            HStack {
                Button("Test key") { Task { await self.model.testAPIKey() } }
                    .disabled(self.model.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                              || self.model.apiKeyLooksInvalid || self.model.keyStatus == .testing)
                Button("Remove key", role: .destructive) { self.model.removeAPIKey() }
                    .disabled(self.model.apiKey.isEmpty)
                keyStatusLabel
            }
            .buttonStyle(PMLSecondaryButtonStyle())
            if let error = self.model.keyStoreError {
                Text(error).font(PMLFont.hint).foregroundStyle(PMLColor.danger)
            }
            Text("Your key is kept in your Mac's Keychain and is only ever sent to Anthropic. You pay Anthropic directly for every request made with your own key.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            TextField("Workspace ID (optional)", text: model.settings.workspaceId)
            Text("Only needed if you see \"anthropic-workspace-id is required\" — that means your key is linked to your identity within an org, not a standalone workspace key.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
        }
    }

    @ViewBuilder private var keyStatusLabel: some View {
        switch model.keyStatus {
        case .untested: EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
            Text("Testing…").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
        case .valid:
            Label("Key works", systemImage: "checkmark.circle.fill").font(PMLFont.hint).foregroundStyle(PMLColor.success)
        case .invalid(let message):
            Label(message, systemImage: "xmark.octagon.fill").font(PMLFont.hint).foregroundStyle(PMLColor.danger)
        }
    }

    private func modelSection(model: Bindable<AppModel>) -> some View {
        Section("Model") {
            Picker("Model", selection: modelSelection) {
                ForEach(ModelCatalog.standardModels) { Text(LocalizedStringKey($0.displayName)).tag($0.id) }
                Text("Other (custom)").tag("other")
            }
            if isStandardModel {
                Text("Selected model: \(self.model.settings.model)").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            } else {
                TextField("Custom model name", text: model.settings.model)
                Text("Enter the exact model string from Anthropic's docs.").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            }
            Picker("Effort", selection: model.settings.effort) {
                ForEach(Effort.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!ModelCatalog.supportsEffort(self.model.settings.model))
            Text("Higher effort produces more thorough results, but takes longer and uses more tokens on your API key.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            if !ModelCatalog.supportsEffort(self.model.settings.model) {
                Text("Claude Haiku 4.5 doesn't support Effort — this only applies to Sonnet, Opus, and Fable models.")
                    .font(PMLFont.hint).foregroundStyle(PMLColor.warning)
            } else if !isStandardModel {
                Text("This custom model may or may not support Effort — if requests start failing, try turning it off.")
                    .font(PMLFont.hint).foregroundStyle(PMLColor.warning)
            }
        }
    }

    private func languageSection(model: Bindable<AppModel>) -> some View {
        Section("Language") {
            LanguageSearchField(selection: model.settings.motherLanguage)
            Text("Used by the \"Translate\" action under Help me → Understand.").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            Picker("App Language", selection: model.settings.appLanguage) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            Text("Only English and Vietnamese are available today. Want Per My Last in your own language? We'd love the help — use Send feedback at the bottom of the app to volunteer translating it.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
        }
    }

    private func generalSection(model: Bindable<AppModel>) -> some View {
        Section("General") {
            Toggle("Show in Dock", isOn: model.settings.showInDock)
            Text("On by default. Turn off to run Per My Last from the menu bar only, with no Dock icon (also toggleable from the tray menu).")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            Text("Starts Per My Last automatically when you log in to your Mac.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            Toggle("Share anonymous setup stats", isOn: model.settings.shareAnonymousUsage)
            Text("Tells us which first-run step people get stuck on. Never includes your text, email, key or anything you select.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
        }
    }

    /// Picker selection that maps any non-standard model ID to the "Other" row.
    private var modelSelection: Binding<String> {
        Binding(
            get: { isStandardModel ? model.settings.model : "other" },
            set: { model.settings.model = ($0 == "other") ? "" : $0 }
        )
    }
}

extension Effort {
    var label: LocalizedStringKey {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra"
        case .max: "Max"
        }
    }
}
