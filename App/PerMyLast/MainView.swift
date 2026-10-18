import PerMyLastCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ShortcutWarningBanner()
                    header
                    tabs(selection: $model.activeMode)
                    chips
                    PromptPanel()
                    inputBox(text: $model.inputText)
                    if model.activeModeTakesIntent {
                        intentRow(text: $model.intent)
                    } else {
                        sendRow
                    }
                    OutputPanel()
                }
                .padding(20)
            }
            Divider()
            FooterBar()
        }
        .frame(minWidth: 380, minHeight: 460)
        .navigationTitle("Per My Last")
        .onChange(of: model.activeMode) { model.selectDefaultPreset() }
        .onChange(of: model.focusToken) { inputFocused = true }
        .onExitCommand { WindowCoordinator.shared.hidePopup() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What are you trying to do?")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.accentColor)
            Text("Say what you mean, but professionally. Saving careers, one email, one message at a time.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func tabs(selection: Binding<String>) -> some View {
        HStack {
            Picker("Mode", selection: selection) {
                ForEach(model.modes, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Button { WindowCoordinator.shared.showSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(model.presetsInActiveMode) { preset in
                    let selected = preset.label == model.selectedLabel
                    Button {
                        model.select(preset)
                    } label: {
                        HStack(spacing: 5) {
                            if !preset.icon.isEmpty { Text(preset.icon) }
                            Text(preset.label).fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { model.selectNeighbour(-1); return .handled }
            .onKeyPress(.rightArrow) { model.selectNeighbour(1); return .handled }
            if let preset = model.currentPreset, !preset.blurb.isEmpty {
                Text(model.blurb(for: preset)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// On tabs that take an intent, Send sits beside the intent field.
    private func intentRow(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your reply intent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 10) {
                TextField("e.g. Confirm I can make it, but ask to push 30 minutes", text: text)
                    .textFieldStyle(.roundedBorder)
                sendButton
            }
        }
    }

    private func inputBox(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .padding(8)
                if text.wrappedValue.isEmpty {
                    Text("Copy some text, then press \(model.shortcutDisplay) — or paste it here.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 150)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            // A paste lands as one big jump in length; run it through the same
            // clean-up as captured text. (Ordinary typing never triggers this.)
            .onChange(of: text.wrappedValue) { old, new in
                if new.count - old.count > 20 { text.wrappedValue = TextCleanup.beautify(new) }
            }
            let words = TextCleanup.wordCount(text.wrappedValue)
            if words > 0 { Text("\(words) words").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var sendRow: some View {
        HStack {
            sendButton
            Spacer()
        }
    }

    private var sendButton: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.send() }
            } label: {
                HStack(spacing: 6) {
                    if model.isSending { ProgressView().controlSize(.small) }
                    Text(LocalizedStringKey(model.isSending ? "Sending…" : (model.hasResult ? "Send again" : "Send")))
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSend)
            .help(sendTooltip)
            Text("⌘↩").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var sendTooltip: String {
        if model.motherLanguageMissing { return L("Set your mother language in Settings first") }
        if model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L("Select or paste text first") }
        return ""
    }
}

// MARK: - Prompt panel

/// The "Prompt" row under the chips: shows the prompt that will be sent, and
/// lets you edit it and save the edit back into the preset.
struct PromptPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let preset = model.currentPreset {
            VStack(alignment: .leading, spacing: 10) {
                header(preset)
                if model.promptOpen {
                    if model.editingPrompt { editor(preset, draft: $model.promptDraft) } else { reader(preset) }
                }
                if let flash = model.savedFlash {
                    Label(flash, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func header(_ preset: Preset) -> some View {
        Button { model.togglePrompt() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .rotationEffect(model.promptOpen ? .degrees(90) : .zero)
                Text("Prompt").font(.callout.weight(.semibold))
                if model.isEdited(preset) {
                    Text("Edited")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
                Spacer()
                if !preset.tone.isEmpty {
                    HStack(spacing: 4) {
                        Text("Tone")
                        Text(preset.tone).fontWeight(.bold)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reader(_ preset: Preset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.motherLanguageMissing
                 ? preset.prompt.replacingOccurrences(of: PresetLibrary.motherLanguageToken, with: "…")
                 : model.resolvedPrompt(for: preset))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: model.openPromptEditor)
                .help("Click to edit")
            if model.motherLanguageMissing {
                Button("your mother language — set it in Settings") { WindowCoordinator.shared.showSettings() }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }

    private func editor(_ preset: Preset, draft: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: draft)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 110)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            Text("Saves to \(model.savedTargetLabel(preset)) in Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.cancelPromptEdit() }
                if model.isEdited(preset) || model.promptDraft != preset.originalPrompt {
                    Button("Reset to original") { model.revertPromptDraft() }
                }
                Spacer()
                Button("Save & overwrite") { model.savePromptEdit() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Output

struct OutputPanel: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        if let error = model.errorMessage {
            errorBox(error)
        } else if model.hasResult {
            result
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("Your draft appears here.").font(.callout.weight(.semibold))
            Text(LocalizedStringKey(model.activeModeTakesIntent
                 ? "Pick a preset above, add your intent if you want, then press ⌘↵."
                 : "Pick a preset above, then press ⌘↵."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func errorBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error: \(message)")
                .foregroundStyle(.red)
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Button("Retry") { Task { await model.send() } }.disabled(!model.canSend)
                if message == AnthropicError.missingAPIKey.errorDescription {
                    Button("Open Settings →") { WindowCoordinator.shared.showSettings() }
                }
                Button("Dismiss") { model.errorMessage = nil }
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(resultTitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Regenerate") { Task { await model.send() } }
                    .disabled(!model.canSend)
                Button(LocalizedStringKey(copied ? "✅ Copied!" : "📋 Copy")) {
                    model.copyOutput()
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
            }
            Text(model.output)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var resultTitle: String {
        guard let preset = model.currentPreset else { return L("Result") }
        return preset.tone.isEmpty ? preset.label : "\(preset.label) · \(preset.tone)"
    }
}

// MARK: - Footer

struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            Text("Version \(model.appVersion)").foregroundStyle(.secondary)
            Spacer()
            Button("Send feedback") { model.sendFeedback() }
            Button("Check for updates") { model.checkForUpdates() }
        }
        .font(.caption)
        .buttonStyle(.link)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}


// MARK: - Shortcut conflict banner

/// Standing warning when the saved shortcut is also used by a common app.
struct ShortcutWarningBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let conflict = model.shortcutAppConflict, !model.shortcutBannerDismissed {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your shortcut (\(model.shortcutDisplay)) is known to conflict with \(conflict.app ?? "")'s \(conflict.description) — it may not always reach Per My Last there. Consider choosing a different combo in Settings.")
                    .font(.callout)
                HStack(spacing: 12) {
                    Button("Open Settings →") { WindowCoordinator.shared.showSettings() }
                    Button("Dismiss") { model.shortcutBannerDismissed = true }
                }
                .buttonStyle(.link)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
