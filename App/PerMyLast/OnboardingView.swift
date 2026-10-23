import PerMyLastCore
import SwiftUI

/// The first-run flow, shown in the popup window in place of the main view until it is finished or skipped.
/// Welcome, then a canned first win (no account, no key, no network), then the shortcut. Access (trial or own key) is
/// not a step of the flow; it opens when someone asks for it, so the first minutes are not spent on setup.
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
            if let current = flow.step.index {
                HStack(spacing: 6) {
                    ForEach(Array(OnboardingModel.Step.sequence.enumerated()), id: \.offset) { i, _ in
                        Capsule()
                            .fill(i <= current ? PMLColor.accent : PMLColor.lineStrong)
                            .frame(width: 28, height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Step \(current + 1) of \(OnboardingModel.Step.sequence.count)"))
            }
            Spacer()
            Button("Skip setup") { flow.skip() }.buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkMuted))
        }
        .padding(.horizontal, PMLSpace.s5)
        .padding(.vertical, PMLSpace.s3)
    }

    private var hasAccess: Bool { !model.apiKey.isEmpty || account.signedIn }

    private var footer: some View {
        HStack(spacing: PMLSpace.s2) {
            if flow.step != .welcome, flow.step != .access {
                Button("Back") { flow.back() }.buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkSoft))
            }
            Spacer()
            switch flow.step {
            case .welcome:
                Button("Show me") { flow.advance() }.buttonStyle(PMLPrimaryButtonStyle())
            case .shortcut:
                Button("Start using Per My Last") { flow.finish() }.buttonStyle(PMLPrimaryButtonStyle())
            case .firstWin:
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
                    Text("Example result").pmlEyebrow()
                    Text(verbatim: shown)
                        .font(PMLFont.input).foregroundStyle(PMLColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func run(_ option: Tone) {
        typing?.cancel()
        tone = option
        shown = ""
        FunnelLog.shared.log(.sampleRun, ["tone": option.rawValue])
        let text = option.sample
        if reduceMotion { shown = text; return }
        typing = Task { @MainActor in
            for character in text {
                if Task.isCancelled { return }
                shown.append(character)
                try? await Task.sleep(for: .milliseconds(14))
            }
        }
    }
}

// MARK: - 3. Shortcut

private struct ShortcutStep: View {
    @Environment(AppModel.self) private var model
    private let flow = OnboardingModel.shared
    @State private var accessGranted = AppModel.canCopySelection

    var body: some View {
        heading("Use it anywhere", "Press one shortcut, in any app.",
                "Select text in Mail, Slack, a browser, anything, then press the shortcut. Per My Last opens with your text ready.")
        HStack(spacing: PMLSpace.s3) {
            KeyCaps(shortcut: shortcutKeys)
            Spacer()
        }
        Label("Not your style? You can change this anytime in Settings.", systemImage: "gearshape")
            .font(PMLFont.select).foregroundStyle(PMLColor.inkMuted)
        accessPanel
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                accessGranted = AppModel.canCopySelection
            }
        tryItPanel
    }

    /// The shortcut as bare key symbols, e.g. "⇧⌘W".
    private var shortcutKeys: String { model.shortcutDisplay.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "+", with: "") }

    /// Numbered eyebrow shared by both steps, so the two panels read as 1 → 2. A finished step shows a check instead.
    private func stepHeader(_ number: Int, _ title: LocalizedStringKey, done: Bool = false) -> some View {
        HStack(spacing: PMLSpace.s2) {
            ZStack {
                Circle().fill(done ? PMLColor.success : PMLColor.accent)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text(verbatim: "\(number)").font(PMLFont.badge).foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            Text(title).pmlEyebrow()
        }
    }

    @ViewBuilder private var accessPanel: some View {
        if accessGranted {
            PMLPanel(fill: PMLColor.surfaceInset) {
                VStack(alignment: .leading, spacing: PMLSpace.s2) {
                    stepHeader(1, "Allow access", done: true)
                    Text("Allowed: Per My Last can read the text you select.")
                        .font(PMLFont.body).foregroundStyle(PMLColor.success)
                }
            }
            .task { await poll() }
        } else {
            PMLBanner {
                VStack(alignment: .leading, spacing: PMLSpace.s2) {
                    stepHeader(1, "Allow access")
                    Text("macOS needs your OK (Accessibility) before Per My Last can read what you select. Without it, the shortcut uses whatever is on your clipboard.")
                        .font(PMLFont.body).foregroundStyle(PMLColor.ink).fixedSize(horizontal: false, vertical: true)
                    AccessGuide()
                    Button("Allow access…") {
                        FunnelLog.shared.log(.accessibilityRequested)
                        AppModel.requestCopyAccess()
                    }.buttonStyle(PMLInkButtonStyle())
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
                stepHeader(2, "Try it now")
                Text("Select the text below…").font(PMLFont.select).fontWeight(.bold).foregroundStyle(PMLColor.ink)
                Text("Hi, could you send me the invoice by Friday? Thank you!")
                    .font(PMLFont.input).foregroundStyle(PMLColor.ink)
                    .textSelection(.enabled)
                    .padding(PMLSpace.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).fill(PMLColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous)
                        .strokeBorder(PMLColor.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                Text("…then press \(model.shortcutDisplay).").font(PMLFont.select).fontWeight(.bold).foregroundStyle(PMLColor.ink)
                if let caught = flow.caught, caught.source == .clipboard {
                    Label("Not yet: it could not read your selection", systemImage: "exclamationmark.triangle.fill")
                        .font(PMLFont.select).foregroundStyle(PMLColor.warning)
                    Text("Per My Last only got what is on your clipboard. Allow access above, then select the text and press the shortcut again.")
                        .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                } else if let caught = flow.caught {
                    Label("It worked!", systemImage: "checkmark.circle.fill")
                        .font(PMLFont.select).foregroundStyle(PMLColor.success)
                    Text(verbatim: "“\(String(caught.text.prefix(120)))”")
                        .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted).lineLimit(2)
                } else {
                    Text("Or try it in any other app. We will notice when it works.")
                        .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                }
            }
        }
    }
}

/// What the user will see in System Settings, drawn and animated here: the pointer finds the Per My Last row and
/// switches it on. Replaces a second "Open System Settings" button that did the same thing as "Allow access…".
private struct AccessGuide: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointerAtToggle = false
    @State private var on = false

    var body: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            Text("Click Allow access, then switch Per My Last on in the list that opens. Come back here after; we notice on our own.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkSoft).fixedSize(horizontal: false, vertical: true)
            mock
                .accessibilityHidden(true)
        }
        .task { await loop() }
    }

    private var mock: some View {
        VStack(spacing: 0) {
            row("Magnet", icon: "rectangle.split.2x1.fill", tint: .blue, toggled: true)
            Rectangle().fill(PMLColor.divider).frame(height: 1)
            row("Per My Last", icon: "envelope.fill", tint: PMLColor.accent, toggled: on, highlight: true)
        }
        .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).fill(PMLColor.surface))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).strokeBorder(PMLColor.lineStrong, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "cursorarrow")
                .font(.system(size: 20))
                .foregroundStyle(PMLColor.ink)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .offset(x: pointerAtToggle ? -14 : 40, y: pointerAtToggle ? -4 : 30)
                .opacity(pointerAtToggle || !reduceMotion ? 1 : 0)
        }
        .frame(maxWidth: 300)
    }

    private func row(_ name: String, icon: String, tint: Color, toggled: Bool, highlight: Bool = false) -> some View {
        HStack(spacing: PMLSpace.s2) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint))
            Text(verbatim: name).font(PMLFont.hint).foregroundStyle(PMLColor.ink)
            Spacer()
            Capsule().fill(toggled ? PMLColor.accent : PMLColor.lineStrong)
                .frame(width: 30, height: 18)
                .overlay(alignment: toggled ? .trailing : .leading) {
                    Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.2), radius: 1)
                }
        }
        .padding(.horizontal, PMLSpace.s3).padding(.vertical, 7)
        .background(highlight ? PMLColor.accentSoft : .clear)
    }

    private func loop() async {
        if reduceMotion { pointerAtToggle = true; on = true; return }
        while !Task.isCancelled {
            on = false; pointerAtToggle = false
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeInOut(duration: 0.8)) { pointerAtToggle = true }
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeInOut(duration: 0.2)) { on = true }
            try? await Task.sleep(for: .milliseconds(1800))
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
        heading("Connect Claude", "Get your first real drafts.",
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

// MARK: - Setup progress (popup, after the flow)

/// A compact reminder in the rail (or above the content when narrow) while setup items are still open.
/// Tapping it reopens the flow at the first open step; it disappears once everything is done.
struct SetupProgressCard: View {
    private let flow = OnboardingModel.shared
    @State private var hovering = false

    var body: some View {
        let items = flow.checklist
        let done = items.filter(\.done).count
        if done < items.count {
            let next = items.first { !$0.done && $0.id != .firstWin }
            let current = items.first { !$0.done }
            Button { if let next { flow.reopen(at: next.id) } } label: {
                VStack(alignment: .leading, spacing: PMLSpace.s2) {
                    HStack {
                        Text("Finish setup").font(PMLFont.select).fontWeight(.bold).foregroundStyle(PMLColor.ink)
                        Spacer(minLength: PMLSpace.s2)
                        Text(verbatim: "\(done)/\(items.count)").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                    }
                    GeometryReader { geo in
                        Capsule().fill(PMLColor.line)
                            .overlay(alignment: .leading) {
                                Capsule().fill(PMLColor.accent).frame(width: geo.size.width * CGFloat(done) / CGFloat(items.count))
                            }
                    }
                    .frame(height: 4)
                    if let current {
                        Text(current.title).font(PMLFont.hint).foregroundStyle(PMLColor.inkSoft)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(PMLSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(hovering && next != nil ? PMLColor.surfaceSunken : PMLColor.surface))
                .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(PMLColor.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}
