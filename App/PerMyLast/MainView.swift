import PerMyLastCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool
    @FocusState private var askFocused: Bool
    @FocusState private var intentFocused: Bool

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let wide = geo.size.width >= PMLLayout.railBreakpoint
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    if wide {
                        ModeRail(modes: model.modes, selection: $model.activeMode, wide: true) { WindowCoordinator.shared.showSettings() }
                            .padding(PMLSpace.s4)
                            .frame(width: PMLLayout.railWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(PMLColor.surfaceInset)
                            .overlay(alignment: .trailing) { Rectangle().fill(PMLColor.divider).frame(width: 1) }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: PMLSpace.s4) {
                            ShortcutWarningBanner()
                            AccountWarningBanner()
                            if wide {
                                description
                            } else {
                                header
                                ModeRail(modes: model.modes, selection: $model.activeMode, wide: false) { WindowCoordinator.shared.showSettings() }
                            }
                            if model.isAsk {
                                askBox(text: $model.askPrompt)
                            } else {
                                chips
                                PromptPanel()
                            }
                            if !model.isAsk { inputBox(text: $model.inputText) }
                            if model.activeModeTakesIntent {
                                intentRow(text: $model.intent)
                            } else {
                                sendRow
                            }
                            OutputPanel()
                        }
                        .padding(wide ? PMLSpace.s5 : PMLLayout.windowPadding)
                    }
                }
                Rectangle().fill(PMLColor.divider).frame(height: 1)
                FooterBar()
            }
        }
        .background(PMLColor.surface)
        .frame(minWidth: PMLLayout.popupMinWidth, minHeight: PMLLayout.popupMinHeight)
        .navigationTitle("Per My Last")
        .onChange(of: model.activeMode) {
            model.selectDefaultPreset()
            if model.isAsk { askFocused = true }
        }
        .onChange(of: model.focusToken) {
            if model.isAsk { askFocused = true } else { inputFocused = true }
        }
        .onExitCommand { WindowCoordinator.shared.hidePopup() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s1) {
            Text("What are you trying to do?").pmlEyebrow()
            description
        }
    }

    private var description: some View {
        Text("Say what you mean, but professionally. Saving careers, one email, one message at a time.")
            .font(PMLFont.body)
            .foregroundStyle(PMLColor.inkSoft)
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            FlowLayout(spacing: 8) {
                ForEach(model.presetsInActiveMode) { preset in
                    let selected = preset.label == model.selectedLabel
                    Button {
                        model.select(preset)
                    } label: {
                        HStack(spacing: 5) {
                            if !preset.icon.isEmpty { Text(preset.icon) }
                            Text(preset.label)
                        }
                    }
                    .buttonStyle(PMLChipStyle(selected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { model.selectNeighbour(-1); return .handled }
            .onKeyPress(.rightArrow) { model.selectNeighbour(1); return .handled }
            if let preset = model.currentPreset, !preset.blurb.isEmpty {
                Text(model.blurb(for: preset)).font(PMLFont.meta).foregroundStyle(PMLColor.inkMuted)
            }
        }
    }

    /// On tabs that take an intent, Send sits beside the intent field.
    private func intentRow(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            Text("Your reply intent").font(PMLFont.meta).fontWeight(.semibold).foregroundStyle(PMLColor.inkMuted)
            HStack(alignment: .center, spacing: PMLSpace.s3) {
                TextField("e.g. Confirm I can make it, but ask to push 30 minutes", text: text)
                    .pmlInput(focus: $intentFocused, height: PMLLayout.controlHeight)
                sendButton
            }
        }
    }

    /// The Ask tab's prompt: a plain box, like a chat app's message field.
    private func askBox(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            Text("Your question").font(PMLFont.meta).fontWeight(.semibold).foregroundStyle(PMLColor.inkMuted)
            PMLField(text: text, placeholder: "Ask anything…", minHeight: 220, focus: $askFocused)
        }
    }

    private func inputBox(text: Binding<String>) -> some View {
        let words = TextCleanup.wordCount(text.wrappedValue)
        return PMLField(
            text: text,
            placeholder: "Select some text, then press \(model.shortcutDisplay) — or paste it here.",
            minHeight: 150, focus: $inputFocused,
            footer: words > 0 ? "\(words) words" : nil)
            // A paste lands as one big jump in length; run it through the same
            // clean-up as captured text. (Ordinary typing never triggers this.)
            .onChange(of: text.wrappedValue) { old, new in
                if new.count - old.count > 20 { text.wrappedValue = TextCleanup.beautify(new) }
            }
    }

    private var sendRow: some View {
        HStack {
            sendButton
            Spacer()
        }
    }

    private var sendButton: some View {
        Button {
            Task { await model.send() }
        } label: {
            HStack(spacing: PMLSpace.s2) {
                if model.isSending { ProgressView().controlSize(.small) }
                Text(LocalizedStringKey(model.isSending ? "Sending…" : (model.hasResult ? "Send again" : "Send")))
                Text("⌘↵").font(PMLFont.kbd).opacity(0.75)
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .buttonStyle(PMLPrimaryButtonStyle())
        .disabled(!model.canSend)
        .help(sendTooltip)
    }

    private var sendTooltip: String {
        if model.motherLanguageMissing { return L("Set your mother language in Settings first") }
        if model.isAsk { return model.askPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("Type your question first") : "" }
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
            PMLPanel(fill: PMLColor.surfaceInset, radius: PMLRadius.inset) {
                VStack(alignment: .leading, spacing: PMLSpace.s3) {
                    header(preset)
                    if model.promptOpen {
                        if model.editingPrompt { editor(preset, draft: $model.promptDraft) } else { reader(preset) }
                    }
                    if let flash = model.savedFlash {
                        Label(flash, systemImage: "checkmark.circle.fill")
                            .font(PMLFont.hint)
                            .foregroundStyle(PMLColor.success)
                    }
                }
            }
        }
    }

    private func header(_ preset: Preset) -> some View {
        Button { model.togglePrompt() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(model.promptOpen ? .degrees(90) : .zero)
                Text("Prompt").font(PMLFont.select).fontWeight(.bold)
                if model.isEdited(preset) {
                    Text("Edited")
                        .font(PMLFont.badge).tracking(0.42).textCase(.uppercase)
                        .foregroundStyle(PMLColor.warning)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(PMLColor.warningSoft, in: RoundedRectangle(cornerRadius: PMLRadius.badge, style: .continuous))
                }
                Spacer()
                if !preset.tone.isEmpty {
                    HStack(spacing: 4) {
                        Text("Tone")
                        Text(preset.tone).fontWeight(.bold)
                    }
                    .font(PMLFont.meta)
                    .foregroundStyle(PMLColor.inkMuted)
                }
            }
            .foregroundStyle(PMLColor.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reader(_ preset: Preset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.motherLanguageMissing
                 ? preset.prompt.replacingOccurrences(of: PresetLibrary.motherLanguageToken, with: "…")
                 : model.resolvedPrompt(for: preset))
                .font(PMLFont.body)
                .foregroundStyle(PMLColor.inkSoft)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: model.openPromptEditor)
                .help("Click to edit")
            if model.writeMyWayApplies(to: preset) {
                Label("Plus your Write My Way settings", systemImage: "wand.and.stars")
                    .font(PMLFont.hint)
                    .foregroundStyle(PMLColor.inkMuted)
            }
            if model.motherLanguageMissing {
                Button("your mother language — set it in Settings") { WindowCoordinator.shared.showSettings() }
                    .buttonStyle(PMLGhostButtonStyle())
            }
        }
    }

    private func editor(_ preset: Preset, draft: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            TextEditor(text: draft)
                .font(PMLFont.body)
                .foregroundStyle(PMLColor.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 110)
                .background(PMLColor.surfaceSunken, in: RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous))
            Text("Saves to \(model.savedTargetLabel(preset)) in Settings")
                .font(PMLFont.hint)
                .foregroundStyle(PMLColor.inkMuted)
            HStack {
                Button("Cancel") { model.cancelPromptEdit() }
                    .buttonStyle(PMLSecondaryButtonStyle())
                if model.isEdited(preset) || model.promptDraft != preset.originalPrompt {
                    Button("Reset to original") { model.revertPromptDraft() }
                        .buttonStyle(PMLGhostButtonStyle())
                }
                Spacer()
                // Send stays the only accent fill in the view.
                Button("Save & overwrite") { model.savePromptEdit() }
                    .buttonStyle(PMLInkButtonStyle())
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
        VStack(spacing: PMLSpace.s1) {
            Text("Your draft appears here.").font(PMLFont.select).fontWeight(.bold).foregroundStyle(PMLColor.ink)
            Text(LocalizedStringKey(model.isAsk
                 ? "Type your question above, then press ⌘↵."
                 : (model.activeModeTakesIntent
                    ? "Pick a preset above, add your intent if you want, then press ⌘↵."
                    : "Pick a preset above, then press ⌘↵.")))
                .font(PMLFont.hint)
                .foregroundStyle(PMLColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(PMLSpace.s5)
        .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.surfaceInset))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(PMLColor.line, lineWidth: 1))
    }

    private func errorBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            Text("Error: \(message)")
                .font(PMLFont.body)
                .foregroundStyle(PMLColor.danger)
                .textSelection(.enabled)
            FlowLayout(spacing: PMLSpace.s1) {
                Button("Retry") { Task { await model.send() } }.disabled(!model.canSend)
                if model.lastErrorKind == .quotaExhausted, AccountModel.shared.entitlement?.ownsLifetime == true, !model.apiKey.isEmpty {
                    Button("Use my own API key instead") {
                        AccountModel.shared.useOwnKey = true
                        model.errorMessage = nil
                        Task { await model.send() }
                    }
                }
                if model.lastErrorKind == .updatesExpired {
                    Button("Renew updates →") { WindowCoordinator.shared.showPaywall() }
                    if let url = URL(string: AppConfig.lastEligibleDownloadURL), !AppConfig.lastEligibleDownloadURL.isEmpty {
                        Link("Download your last version", destination: url)
                            .font(PMLFont.select).foregroundStyle(PMLColor.accentText)
                    }
                }
                if model.lastErrorKind == .noEntitlement || model.lastErrorKind == .trialExpired || model.lastErrorKind == .trialCreditsExhausted {
                    Button("See plans →") { WindowCoordinator.shared.showPaywall() }
                }
                if message == AnthropicError.missingAPIKey.errorDescription {
                    Button("Open Settings →") { WindowCoordinator.shared.showSettings() }
                }
                Button("Dismiss") { model.errorMessage = nil }
            }
            .buttonStyle(PMLGhostButtonStyle())
        }
        .padding(PMLSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.dangerSoft))
    }

    private var result: some View {
        PMLPanel {
            VStack(alignment: .leading, spacing: PMLSpace.s3) {
                HStack(spacing: PMLSpace.s2) {
                    Text(verbatim: resultTitle).pmlEyebrow(PMLColor.inkMuted).lineLimit(1)
                    Spacer()
                    Button("Regenerate") { Task { await model.send() } }
                        .buttonStyle(PMLSecondaryButtonStyle())
                        .disabled(!model.canSend)
                    Button(LocalizedStringKey(copied ? "✅ Copied!" : "📋 Copy")) {
                        model.copyOutput()
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    .buttonStyle(PMLInkButtonStyle())
                }
                Text(model.output)
                    .font(PMLFont.input)
                    .foregroundStyle(PMLColor.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var resultTitle: String {
        if model.isAsk { return L("Ask") }
        guard let preset = model.currentPreset else { return L("Result") }
        return preset.tone.isEmpty ? preset.label : "\(preset.label) · \(preset.tone)"
    }
}

// MARK: - Footer

struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: PMLSpace.s4) {
            Text("Version \(model.appVersion)").foregroundStyle(PMLColor.inkMuted)
            UsageMeterLabel()
            Spacer()
            Button("Send feedback") { model.sendFeedback() }
                .buttonStyle(PMLGhostButtonStyle())
                .fixedSize()
        }
        .font(PMLFont.hint)
        .padding(.horizontal, PMLLayout.windowPadding)
        .padding(.vertical, PMLSpace.s2)
        .background(PMLColor.surface)
    }
}


// MARK: - Shortcut conflict banner

/// Standing warning when the saved shortcut is also used by a common app.
struct ShortcutWarningBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let conflict = model.shortcutAppConflict, !model.shortcutBannerDismissed {
            PMLBanner {
                VStack(alignment: .leading, spacing: PMLSpace.s2) {
                    Label {
                        Text("Your shortcut (\(model.shortcutDisplay)) is known to conflict with \(conflict.app ?? "")'s \(conflict.description) — it may not always reach Per My Last there. Consider choosing a different combo in Settings.")
                            .font(PMLFont.body)
                            .foregroundStyle(PMLColor.ink)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(PMLColor.warning)
                    }
                    HStack(spacing: PMLSpace.s2) {
                        Button("Open Settings →") { WindowCoordinator.shared.showSettings() }
                            .buttonStyle(PMLInkButtonStyle())
                        Button("Dismiss") { model.shortcutBannerDismissed = true }
                            .buttonStyle(PMLGhostButtonStyle())
                    }
                }
            }
        }
    }
}
