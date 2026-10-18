import PerMyLastCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var customModel = ""

    private var isStandardModel: Bool {
        ModelCatalog.standardModels.contains { $0.id == model.settings.model }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Anthropic") {
                SecureField("API key", text: $model.apiKey, prompt: Text("sk-ant-…"))
                    .onChange(of: model.apiKey) { model.saveAPIKey() }
                Text("Your key stays in the macOS Keychain. Requests go straight from your Mac to Anthropic — Per My Last has no server.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Workspace ID", text: $model.settings.workspaceId, prompt: Text("Only for identity-linked keys"))
            }

            Section("Model") {
                Picker("Model", selection: modelSelection(model)) {
                    ForEach(ModelCatalog.standardModels) { Text($0.displayName).tag($0.id) }
                    Text("Other (custom)").tag("other")
                }
                if !isStandardModel {
                    TextField("Model ID", text: $model.settings.model, prompt: Text("e.g. claude-sonnet-5"))
                }
                Picker("Effort", selection: $model.settings.effort) {
                    ForEach(Effort.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!ModelCatalog.supportsEffort(model.settings.model))
            }

            Section("Language") {
                Picker("Mother language", selection: $model.settings.motherLanguage) {
                    Text("Not set").tag("")
                    ForEach(Languages.all) { Text("\($0.flag) \($0.name)").tag($0.name) }
                }
                Text("What “Translate” translates into.").font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Show in Dock", isOn: $model.settings.showInDock)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                LabeledContent("Shortcut", value: "⌘⇧W")
                if let error = model.hotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { model.saveSettings() }
        
    }

    /// Picker selection that maps any non-standard model ID to the "Other" row.
    private func modelSelection(_ model: AppModel) -> Binding<String> {
        Binding(
            get: { isStandardModel ? model.settings.model : "other" },
            set: { model.settings.model = ($0 == "other") ? "" : $0 }
        )
    }
}

private extension Effort {
    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra"
        case .max: "Max"
        }
    }
}
