import PerMyLastCore
import ServiceManagement
import SwiftUI

/// The first-run flow, shown in the popup window in place of the main view until it is finished or skipped.
/// Welcome, then a canned first win (no account, no key, no network), then the shortcut, then access (trial or own key).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    private let flow = OnboardingModel.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            if Self.snapshotMode { stepContent } else { ScrollView { stepContent } }
            Rectangle().fill(PMLColor.divider).frame(height: 1)
            footer
        }
        .background(PMLColor.surface)
        .onAppear { flow.didAppear() }
        .animation(PMLMotion.base, value: flow.step)
    }

    /// Dev only (`PML_SNAPSHOT`): ImageRenderer draws ScrollViews blank, so snapshots lay the step out plainly.
    static var snapshotMode = false

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s4) {
            switch flow.step {
            case .welcome: WelcomeStep()
            case .firstWin: FirstWinStep()
            case .shortcut: ShortcutStep()
            case .access: AccessStep()
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(PMLSpace.s5)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: PMLSpace.s3) {
            HStack(spacing: 6) {
                ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.index <= flow.step.index ? PMLColor.accent : PMLColor.lineStrong)
                        .frame(width: 28, height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(flow.step.index + 1) of \(OnboardingModel.Step.allCases.count)"))
            Spacer()
            Button("Skip setup") { flow.skip() }.buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkMuted))
        }
        .padding(.horizontal, PMLSpace.s5)
        .padding(.vertical, PMLSpace.s3)
    }

    private var hasAccess: Bool { !model.apiKey.isEmpty || account.signedIn }

    private var footer: some View {
        HStack(spacing: PMLSpace.s2) {
            if flow.step != .welcome {
                Button("Back") { flow.back() }.buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkSoft))
            }
            Spacer()
            switch flow.step {
            case .welcome:
                Button("Show me") { flow.advance() }.buttonStyle(PMLPrimaryButtonStyle())
            case .firstWin, .shortcut:
                Button("Next") { flow.advance() }.buttonStyle(PMLPrimaryButtonStyle())
            case .access:
                if !hasAccess { Button("Skip for now") { flow.skip() }.buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkSoft)) }
                Button("Start using Per My Last") { flow.finish() }
                    .buttonStyle(PMLPrimaryButtonStyle())
                    .disabled(!hasAccess)
            }
        }
        .padding(.horizontal, PMLSpace.s5)
        .padding(.vertical, PMLSpace.s3)
        .background(PMLColor.surface)
    }
}

// MARK: - Shared bits

private func heading(_ eyebrow: LocalizedStringKey, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: PMLSpace.s2) {
        Text(eyebrow).pmlEyebrow()
        Text(title).font(.custom("Plus Jakarta Sans", size: 24).weight(.bold)).foregroundStyle(PMLColor.ink)
        Text(subtitle).font(PMLFont.input).foregroundStyle(PMLColor.inkSoft).fixedSize(horizontal: false, vertical: true)
    }
}

/// The shortcut drawn as key caps.
private struct KeyCaps: View {
    let shortcut: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(shortcut.enumerated()), id: \.offset) { _, key in
                Text(String(key))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(PMLColor.ink)
                    .frame(minWidth: 38, minHeight: 38)
                    .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).fill(PMLColor.surfaceSunken))
                    .overlay(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).strokeBorder(PMLColor.lineStrong, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: shortcut))
    }
}

// MARK: - 1. Welcome

private struct WelcomeStep: View {
    var body: some View {
        heading("Welcome", "Say it right, every time.",
                "Select text in any app, press a shortcut, and get a calm, professional version back. Takes about a minute to set up.")
        VStack(spacing: PMLSpace.s2) {
            PMLPanel(fill: PMLColor.surfaceInset) {
                VStack(alignment: .leading, spacing: PMLSpace.s1) {
                    Text("You wrote").pmlEyebrow(PMLColor.inkMuted)
                    Text(verbatim: L("hey, just following up AGAIN on the invoice. it's been 3 weeks. need this sorted asap"))
                        .font(PMLFont.input).foregroundStyle(PMLColor.inkSoft)
                }
            }
            Image(systemName: "arrow.down").foregroundStyle(PMLColor.inkMuted)
            PMLPanel {
                VStack(alignment: .leading, spacing: PMLSpace.s1) {
                    Text("You send").pmlEyebrow()
                    Text(verbatim: L("Hi, I wanted to follow up on the invoice from three weeks ago. Could you let me know when I can expect payment? Thank you for your help."))
                        .font(PMLFont.input).foregroundStyle(PMLColor.ink)
                }
            }
        }
        Text("No account needed to try it.").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
    }
}

// MARK: - 2. First win

private struct FirstWinStep: View {
    private let flow = OnboardingModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tone: Tone?
    @State private var shown = ""
    @State private var finished = false
    @State private var copied = false
    @State private var typing: Task<Void, Never>?

    enum Tone: String, CaseIterable {
        case polite, direct, friendly
        var label: LocalizedStringKey {
            switch self {
            case .polite: "Polite"
            case .direct: "Direct"
            case .friendly: "Friendly"
            }
        }
        @MainActor var sample: String {
            switch self {
            case .polite: L("Hi, I wanted to follow up on the invoice from three weeks ago. Could you let me know when I can expect payment? Thank you for your help.")
            case .direct: L("Hi, the invoice from three weeks ago is still unpaid. Please confirm a payment date by Friday.")
            case .friendly: L("Hi! Just a gentle nudge about the invoice from a few weeks back. Any chance you could take a look this week? Thanks so much!")
            }
        }
    }

    var body: some View {
        heading("Try it", "Fix a message in one click.",
                "Here is a message that could go better. Pick a tone and watch it get rewritten.")
        PMLPanel(fill: PMLColor.surfaceInset) {
            VStack(alignment: .leading, spacing: PMLSpace.s1) {
                Text("Original").pmlEyebrow(PMLColor.inkMuted)
                Text(verbatim: L("hey, just following up AGAIN on the invoice. it's been 3 weeks. need this sorted asap"))
                    .font(PMLFont.input).foregroundStyle(PMLColor.inkSoft)
            }
        }
        FlowLayout(spacing: 8) {
            ForEach(Tone.allCases, id: \.self) { option in
                Button { run(option) } label: { Text(option.label) }
                    .buttonStyle(PMLChipStyle(selected: tone == option))
                    .accessibilityAddTraits(tone == option ? .isSelected : [])
            }
        }
        result
        Text("This is an example, so nothing is sent anywhere. Your real drafts come from Claude.")
            .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
    }

    @ViewBuilder private var result: some View {
        if tone != nil {
            PMLPanel {
                VStack(alignment: .leading, spacing: PMLSpace.s3) {
                    HStack {
                        Text("Example result").pmlEyebrow()
                        Spacer()
                        if finished {
                            Button(LocalizedStringKey(copied ? "✅ Copied!" : "📋 Copy")) { copy() }
                                .buttonStyle(PMLInkButtonStyle())
                        }
                    }
                    Text(verbatim: shown)
                        .font(PMLFont.input).foregroundStyle(PMLColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    if copied {
                        Text("That is the whole loop: select, shortcut, pick a tone, copy. Paste it anywhere.")
                            .font(PMLFont.hint).foregroundStyle(PMLColor.success)
                    }
                }
            }
        }
    }

    private func run(_ option: Tone) {
        typing?.cancel()
        tone = option
        finished = false
        copied = false
        shown = ""
        FunnelLog.shared.log(.sampleRun, ["tone": option.rawValue])
        let text = option.sample
        if reduceMotion { shown = text; finished = true; return }
        typing = Task { @MainActor in
            for character in text {
                if Task.isCancelled { return }
                shown.append(character)
                try? await Task.sleep(for: .milliseconds(14))
            }
            finished = true
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shown, forType: .string)
        copied = true
        FunnelLog.shared.log(.copyClicked)
    }
}

// MARK: - 3. Shortcut

private struct ShortcutStep: View {
    @Environment(AppModel.self) private var model
    private let flow = OnboardingModel.shared
    @State private var accessGranted = AppModel.canCopySelection
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        heading("Use it anywhere", "Press one shortcut, in any app.",
                "Select text in Mail, Slack, a browser, anything, then press the shortcut. Per My Last opens with your text ready.")
        HStack(spacing: PMLSpace.s3) {
            KeyCaps(shortcut: shortcutKeys)
            Spacer()
            Button("Change…") { WindowCoordinator.shared.showSettings() }.buttonStyle(PMLGhostButtonStyle())
        }
        accessPanel
        tryItPanel
        keepHandy
    }

    /// The shortcut as bare key symbols, e.g. "⇧⌘W".
    private var shortcutKeys: String { model.shortcutDisplay.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "+", with: "") }

    @ViewBuilder private var accessPanel: some View {
        if accessGranted {
            Label("Allowed: Per My Last can read the text you select.", systemImage: "checkmark.circle.fill")
                .font(PMLFont.body).foregroundStyle(PMLColor.success)
                .task { await poll() }
        } else {
            PMLBanner {
                VStack(alignment: .leading, spacing: PMLSpace.s2) {
                    Label {
                        Text("macOS needs your OK (Accessibility) before Per My Last can read what you select. Without it, the shortcut uses whatever is on your clipboard.")
                            .font(PMLFont.body).foregroundStyle(PMLColor.ink)
                    } icon: { Image(systemName: "hand.raised.fill").foregroundStyle(PMLColor.warning) }
                    HStack(spacing: PMLSpace.s2) {
                        Button("Allow access…") {
                            FunnelLog.shared.log(.accessibilityRequested)
                            _ = CGRequestPostEventAccess()
                        }.buttonStyle(PMLInkButtonStyle())
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                        }.buttonStyle(PMLGhostButtonStyle())
                    }
                    Text("Prefer not to? Select text, then right-click and choose Services, Open in Per My Last. That needs no permission.")
                        .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                }
            }
            .task { await poll() }
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            accessGranted = AppModel.canCopySelection
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private var tryItPanel: some View {
        PMLPanel(fill: PMLColor.surfaceInset) {
            VStack(alignment: .leading, spacing: PMLSpace.s2) {
                Text("Try it now").pmlEyebrow()
                Text("Select this sentence, then press \(model.shortcutDisplay).")
                    .font(PMLFont.input).foregroundStyle(PMLColor.ink)
                    .textSelection(.enabled)
                if let caught = flow.caught {
                    Label("It worked!", systemImage: "checkmark.circle.fill")
                        .font(PMLFont.select).foregroundStyle(PMLColor.success)
                    Text(verbatim: "“\(String(caught.text.prefix(120)))”")
                        .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted).lineLimit(2)
                    if caught.source == .clipboard {
                        Text("It used your clipboard, not your selection. Allow access above and it will read what you select.")
                            .font(PMLFont.hint).foregroundStyle(PMLColor.warning)
                    }
                } else {
                    Text("Or try it in any other app. We will notice when it works.")
                        .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                }
            }
        }
    }

    private var keepHandy: some View {
        PMLPanel {
            VStack(alignment: .leading, spacing: PMLSpace.s2) {
                Label("Closing this window does not quit the app. Look for the umbrella in your menu bar.", systemImage: "menubar.arrow.up.rectangle")
                    .font(PMLFont.body).foregroundStyle(PMLColor.inkSoft)
                Toggle("Open Per My Last when I log in", isOn: $launchAtLogin)
                    .font(PMLFont.body)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
        }
    }
}

// MARK: - 4. Access

private struct AccessStep: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var keyTest: Task<Void, Never>?
    @State private var loggedKey = false
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool

    var body: some View {
        heading("Last step", "Get your first real drafts.",
                "Choose how Per My Last reaches Claude. You can change this any time in Settings.")
        if account.isConfigured { trialCard }
        keyCard
    }

    // MARK: Trial

    private var trialCard: some View {
        PMLPanel {
            VStack(alignment: .leading, spacing: PMLSpace.s3) {
                HStack {
                    Text("Start your free trial").font(PMLFont.cardTitle).foregroundStyle(PMLColor.ink)
                    Spacer()
                    Text("Recommended").font(PMLFont.badge).textCase(.uppercase).tracking(0.42)
                        .foregroundStyle(PMLColor.accentText)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(PMLColor.accentSoft))
                }
                Text("\(AppConfig.trialRuns) runs over \(AppConfig.trialDays) days. No card, no key to find.")
                    .font(PMLFont.body).foregroundStyle(PMLColor.inkSoft)
                if account.signedIn {
                    Label(account.meterText ?? L("Trial started"), systemImage: "checkmark.circle.fill")
                        .font(PMLFont.select).foregroundStyle(PMLColor.success)
                } else {
                    emailForm
                }
                if let message = account.message, !account.signedIn {
                    Text(message).font(PMLFont.hint).foregroundStyle(account.messageIsError ? PMLColor.danger : PMLColor.inkMuted)
                }
            }
        }
    }

    @ViewBuilder private var emailForm: some View {
        @Bindable var account = account
        switch account.emailStep {
        case .enterEmail:
            HStack(spacing: PMLSpace.s2) {
                TextField("you@example.com", text: $account.email)
                    .textContentType(.emailAddress)
                    .pmlInput(focus: $emailFocused)
                    .onSubmit { sendCode() }
                Button("Email me a code") { sendCode() }
                    .buttonStyle(PMLPrimaryButtonStyle(size: .compact))
                    .disabled(self.account.isBusy || self.account.email.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        case .enterCode:
            HStack(spacing: PMLSpace.s2) {
                TextField("6-digit code", text: $account.code)
                    .pmlInput(focus: $codeFocused)
                    .onSubmit { verify() }
                Button("Start trial") { verify() }
                    .buttonStyle(PMLPrimaryButtonStyle(size: .compact))
                    .disabled(self.account.isBusy || self.account.code.trimmingCharacters(in: .whitespaces).count != 6)
            }
            Button("Use a different email") { self.account.useDifferentEmail() }.buttonStyle(PMLGhostButtonStyle())
        }
    }

    private func sendCode() {
        Task {
            await account.sendCode()
            if account.emailStep == .enterCode { FunnelLog.shared.log(.trialCodeSent); codeFocused = true }
        }
    }

    private func verify() {
        Task {
            await account.verifyCode()
            if account.signedIn { FunnelLog.shared.log(.trialStarted) }
        }
    }

    // MARK: Own key

    private var keyCard: some View {
        @Bindable var model = model
        return PMLPanel(fill: PMLColor.surfaceInset) {
            VStack(alignment: .leading, spacing: PMLSpace.s3) {
                Text("I already have a Claude API key").font(PMLFont.cardTitle).foregroundStyle(PMLColor.ink)
                SecureField("sk-ant-…", text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: self.model.apiKey) { self.model.saveAPIKey(); scheduleTest() }
                keyStatus
                HStack(spacing: 4) {
                    Text("Get one at")
                    Link("console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                Text("Kept in your Mac's Keychain and only sent to Anthropic. You pay Anthropic directly.")
                    .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            }
        }
    }

    @ViewBuilder private var keyStatus: some View {
        if model.apiKeyLooksInvalid {
            Text("API key must start with \"sk-ant-\"").font(PMLFont.hint).foregroundStyle(PMLColor.danger)
        }
        switch model.keyStatus {
        case .untested: EmptyView()
        case .testing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking your key…").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted) }
        case .valid:
            Label("Key works", systemImage: "checkmark.circle.fill").font(PMLFont.select).foregroundStyle(PMLColor.success)
        case .invalid(let message):
            Label(message, systemImage: "xmark.octagon.fill").font(PMLFont.hint).foregroundStyle(PMLColor.danger)
        }
    }

    /// Tests a pasted key by itself, so there is no extra button to find.
    private func scheduleTest() {
        keyTest?.cancel()
        let key = model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-ant-"), key.count > 30 else { return }
        keyTest = Task {
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            await model.testAPIKey()
            if model.keyStatus == .valid, !loggedKey { loggedKey = true; FunnelLog.shared.log(.ownKeySaved) }
        }
    }
}

// MARK: - Checklist (popup, after the flow)

/// Replaces the empty output panel while setup items are still open.
struct GettingStartedChecklist: View {
    private let flow = OnboardingModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            Text("Getting started").font(PMLFont.cardTitle).foregroundStyle(PMLColor.ink)
            ForEach(flow.checklist) { item in
                HStack(spacing: PMLSpace.s2) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.done ? PMLColor.success : PMLColor.inkHint)
                    Text(item.title).font(PMLFont.body)
                        .foregroundStyle(item.done ? PMLColor.inkMuted : PMLColor.ink)
                        .strikethrough(item.done)
                    Spacer()
                    if !item.done, item.id != .firstWin {
                        Button("Set up") { flow.reopen(at: item.id) }.buttonStyle(PMLGhostButtonStyle())
                    }
                }
            }
        }
        .padding(PMLSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.surfaceInset))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(PMLColor.line, lineWidth: 1))
    }
}
