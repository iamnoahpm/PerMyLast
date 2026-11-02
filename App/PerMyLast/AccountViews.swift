import PerMyLastCore
import SwiftUI

/// Settings → General → Account: sign in, plan meter, sign out. Only shown when a backend is configured.
struct AccountSection: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account
    @State private var confirmingDelete = false

    var body: some View {
        @Bindable var account = account
        if account.isConfigured {
            Section("Account") {
                if account.signedIn { signedIn(account: $account) } else { signedOut(account: $account) }
                if let message = account.message {
                    Text(message).font(PMLFont.hint).foregroundStyle(account.messageIsError ? PMLColor.danger : PMLColor.inkMuted)
                }
            }
        }
    }

    @ViewBuilder private func signedOut(account: Bindable<AccountModel>) -> some View {
        Text("Sign in to use your free credits.").foregroundStyle(PMLColor.inkMuted)
        if AppConfig.emailSignInEnabled { emailSignIn(account: account) }
        if AppConfig.appleSignInEnabled || AppConfig.googleSignInEnabled {
            HStack {
                if AppConfig.appleSignInEnabled { Button("Sign in with Apple") { self.account.signInWithApple() } }
                if AppConfig.googleSignInEnabled { Button("Sign in with Google") { Task { await self.account.signInWithGoogle() } } }
            }
            .disabled(self.account.isBusy)
        }
    }

    @ViewBuilder private func emailSignIn(account: Bindable<AccountModel>) -> some View {
        switch self.account.emailStep {
        case .enterEmail:
            HStack {
                TextField("Email", text: account.email, prompt: Text("you@example.com"))
                    .textContentType(.emailAddress)
                    .onSubmit { Task { await self.account.sendCode() } }
                Button("Send code") { Task { await self.account.sendCode() } }
                    .buttonStyle(PMLSecondaryButtonStyle())
                    .disabled(self.account.isBusy || self.account.email.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        case .enterCode:
            HStack {
                TextField("6-digit code", text: account.code)
                    .onSubmit { Task { await self.account.verifyCode() } }
                Button("Sign in") { Task { await self.account.verifyCode() } }
                    .buttonStyle(PMLSecondaryButtonStyle())
                    .disabled(self.account.isBusy || self.account.code.trimmingCharacters(in: .whitespaces).count != 6)
                Button("Use a different email") { self.account.useDifferentEmail() }.buttonStyle(PMLGhostButtonStyle())
            }
        }
    }

    @ViewBuilder private func signedIn(account: Bindable<AccountModel>) -> some View {
        if let method = self.account.signInMethodText {
            LabeledContent {
                Text(verbatim: self.account.accountTitle).textSelection(.enabled)
            } label: {
                Label(method, systemImage: self.account.entitlement?.provider == .apple ? "apple.logo" : "person.crop.circle")
            }
            if self.account.displayName != nil, let email = self.account.identity.title {
                LabeledContent("Email") { Text(verbatim: email).textSelection(.enabled) }
            }
            if let relay = self.account.identity.detail {
                LabeledContent("Email") { Text(verbatim: relay).textSelection(.enabled) }
            }
            if let note = self.account.hiddenEmailNote {
                Text(note).font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            }
        }
        if let meter = self.account.meterText {
            Label(meter, systemImage: "gauge.with.dots.needle.33percent")
        } else {
            Label("Signed in", systemImage: "person.crop.circle.badge.checkmark")
        }
        if let me = self.account.entitlement, me.plan.isPro, !model.apiKey.isEmpty,
           me.ownsLifetime || !AppConfig.ownKeyNeedsLicense {
            Toggle("Use my own API key instead", isOn: account.useOwnKey)
        }
        HStack {
            if self.account.entitlement?.plan.isPro != true { Button("Upgrade…") { WindowCoordinator.shared.showPaywall() } }
            Button("Restore purchases") { Task { await PurchaseService.shared.restore() } }
            Button("Refresh") { Task { await self.account.refreshEntitlement() } }
            Button("Sign out") { self.account.signOut() }
        }
        .buttonStyle(PMLSecondaryButtonStyle())
        Button("Delete account…", role: .destructive) { confirmingDelete = true }
            .buttonStyle(PMLGhostButtonStyle())
            .disabled(self.account.isBusy)
            .confirmationDialog(Text(verbatim: self.account.deleteTitle), isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { _ = await self.account.deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(verbatim: self.account.deleteMessage)
            }
    }
}

extension AccountModel {
    /// The footer's credits state for Free and Pro. Nil while the plan is loading, signed out, or on Lifetime
    /// (the person's own Anthropic key, so there is no count to show).
    var creditsFooterState: CreditsFooterState? {
        guard isConfigured, signedIn, let me = entitlement, me.plan == .free || me.plan.isPro,
              let left = me.runsLeft else { return nil }
        return getCreditsFooterState(remaining: left, total: me.runsAllowance, resetDate: me.periodEnd)
    }
}

/// The footer's wording, localized. Strings follow the design handoff exactly.
@MainActor
enum CreditsCopy {
    private static func number(_ n: Int) -> String { n.formatted(.number.locale(AppModel.shared.locale)) }

    static func creditsLeft(_ n: Int) -> String {
        n == 1 ? L("1 credit left") : L("\(number(n)) credits left")
    }

    static func reset(_ reset: CreditsReset) -> String {
        switch reset {
        case .today: return L("resets today")
        case .tomorrow: return L("resets tomorrow")
        case .days(let n): return L("resets in \(n) days")
        }
    }

    /// The visible line: "999 credits left", "Running low: 180 credits left · resets in 26 days", "No credits left · resets today".
    static func text(_ s: CreditsFooterState) -> String {
        let tail = s.reset.map { " · " + reset($0) } ?? ""
        switch s.level {
        case .normal: return creditsLeft(s.remaining)
        case .low: return L("Running low: \(creditsLeft(s.remaining))") + tail
        case .empty: return L("No credits left") + tail
        }
    }

    /// "999 of 1,021 credits · resets in 26 days (26 Nov 2026)"; also carries the full text when the line is truncated.
    static func tooltip(_ s: CreditsFooterState, resetDate: Date?) -> String {
        var out = s.total.map { L("\(number(s.remaining)) of \(number($0)) credits") } ?? creditsLeft(s.remaining)
        if let r = s.reset {
            out += " · " + reset(r)
            if let resetDate {
                out += " (" + resetDate.formatted(.dateTime.day().month(.abbreviated).year().locale(AppModel.shared.locale)) + ")"
            }
        }
        return out
    }
}

/// Footer indicator (FR-A13): quiet while there are plenty of credits, louder as they run low. State is told by
/// words as well as colour. Lifetime keeps its plain "Using your Anthropic key" line.
struct UsageMeterLabel: View {
    @Environment(AccountModel.self) private var account

    var body: some View {
        if let state = account.creditsFooterState {
            let tip = CreditsCopy.tooltip(state, resetDate: account.entitlement?.periodEnd)
            switch state.level {
            case .normal:
                HStack(spacing: PMLSpace.s2) {
                    CreditsBar(ratio: state.ratio, fill: PMLColor.accent, track: PMLColor.line)
                    line(state).foregroundStyle(PMLColor.inkMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(tip)
                .focusableTooltip(tip)
            case .low:
                HStack(spacing: PMLSpace.s2) {
                    CreditsBar(ratio: state.ratio, fill: PMLColor.warning, track: PMLColor.warningLine)
                    line(state).fontWeight(.medium).foregroundStyle(PMLColor.warning)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 10)
                .background(Capsule().fill(PMLColor.warningSoft))
                .overlay(Capsule().strokeBorder(PMLColor.warningLine, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityHint(tip)
                .focusableTooltip(tip)
            case .empty:
                HStack(spacing: PMLSpace.s2) {
                    line(state).fontWeight(.medium).foregroundStyle(PMLColor.danger)
                        .lineLimit(1).truncationMode(.tail).help(tip)
                    Button("Upgrade") { WindowCoordinator.shared.showPaywall() }
                        .buttonStyle(FooterUpgradeButtonStyle())
                }
            }
        } else if account.entitlement?.plan == .lifetime, let text = account.meterText {
            Text(text).foregroundStyle(PMLColor.inkMuted).lineLimit(1).truncationMode(.tail)
        }
    }

    /// One line that ellipsizes on a narrow window; the tooltip holds the full text.
    private func line(_ state: CreditsFooterState) -> Text {
        Text(verbatim: CreditsCopy.text(state))
    }
}

/// 56 x 4 pt track with a fill of `ratio`. Decorative: the words beside it say the same thing. Hidden when the total is unknown.
private struct CreditsBar: View {
    let ratio: Double?
    let fill: Color
    let track: Color

    var body: some View {
        if let ratio {
            Capsule().fill(track)
                .frame(width: 56, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(fill).frame(width: 56 * min(1, max(0, ratio)))
                }
                .clipShape(Capsule())
                .accessibilityHidden(true)
        }
    }
}

private extension View {
    /// The full text as a small bubble on hover and on keyboard focus.
    func focusableTooltip(_ text: String) -> some View { modifier(FocusableTooltip(text: text)) }
}

private struct FocusableTooltip: ViewModifier {
    let text: String
    @FocusState private var focused: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .lineLimit(1).truncationMode(.tail)
            .pmlFocusRing(radius: PMLRadius.badge)
            // Keyboard navigation only: a click must not leave the bubble stuck open.
            .focusable(interactions: .activate)
            .focusEffectDisabled()
            .focused($focused)
            // Escape dismisses the bubble instead of closing the window.
            .onExitCommand { if focused { focused = false } else { WindowCoordinator.shared.hidePopup() } }
            // Shown while the pointer is over it or it has keyboard focus. Moving away, which includes clicking
            // elsewhere, dismisses it; so does Escape.
            .onHover { inside in
                hovering = inside
                if !inside { focused = false }
            }
            .overlay(alignment: .topTrailing) {
                if hovering || focused {
                    Text(verbatim: text)
                        .font(PMLFont.hint).foregroundStyle(PMLColor.ink)
                        .padding(.horizontal, PMLSpace.s2).padding(.vertical, PMLSpace.s1)
                        .background(RoundedRectangle(cornerRadius: PMLRadius.badge, style: .continuous).fill(PMLColor.surface))
                        .overlay(RoundedRectangle(cornerRadius: PMLRadius.badge, style: .continuous).strokeBorder(PMLColor.lineStrong, lineWidth: 1))
                        .fixedSize()
                        .offset(y: -34)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// The Upgrade button in the out-of-credits footer: accent fill, hover darkens and lifts 1 pt (no lift under Reduce Motion).
private struct FooterUpgradeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PMLFont.body.weight(.semibold))
            .foregroundStyle(PMLColor.onAccent)
            .padding(.vertical, 6).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: PMLRadius.btn, style: .continuous)
                .fill(hovering || configuration.isPressed ? PMLColor.accentHover : PMLColor.accent))
            .contentShape(RoundedRectangle(cornerRadius: PMLRadius.btn, style: .continuous))
            .pmlFocusRing(radius: PMLRadius.btn)
            .offset(y: hovering && !configuration.isPressed && !reduceMotion ? PMLMotion.lift : 0)
            .animation(PMLMotion.fast, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// One-time heads-up at 80% of the allowance and three days before the trial ends (FR-A14).
struct AccountWarningBanner: View {
    @Environment(AccountModel.self) private var account

    var body: some View {
        if let warning = account.warning {
            PMLBanner {
                HStack(spacing: PMLSpace.s2) {
                    Label {
                        Text(warning).font(PMLFont.body).foregroundStyle(PMLColor.ink)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(PMLColor.warning)
                    }
                    Spacer()
                    Button("Dismiss") { account.warning = nil }.buttonStyle(PMLGhostButtonStyle())
                }
            }
        }
    }
}

/// Bottom of the left rail: who is using the app and the way into Settings.
/// A guest is nudged to sign in so their setup is saved; a signed-in user sees their plan and usage meter.
struct AccountFooter: View {
    @Environment(AccountModel.self) private var account
    @State private var hovering = false

    private var title: String {
        guard account.signedIn else { return L("Guest") }
        return account.accountTitle
    }

    private var subtitle: String? {
        if account.signedIn { return [account.planTitle, account.usageText].compactMap { $0 }.joined(separator: " · ") }
        return account.isConfigured ? L("Sign in to save your setup") : nil
    }

    var body: some View {
        Button { WindowCoordinator.shared.showSettings() } label: {
            HStack(spacing: PMLSpace.s2) {
                UmbrellaAvatar(active: account.signedIn, provider: account.signedIn ? account.entitlement?.provider : nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).font(PMLFont.select).fontWeight(.bold).foregroundStyle(PMLColor.ink)
                        .lineLimit(1).truncationMode(.middle)
                    if let subtitle {
                        Text(verbatim: subtitle).font(PMLFont.hint)
                            .foregroundStyle(account.signedIn ? PMLColor.inkMuted : PMLColor.accentText)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(PMLColor.inkSoft)
            }
            .padding(PMLSpace.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(hovering ? PMLColor.surfaceSunken : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Settings")
    }
}


/// The app mark (seven-panel umbrella seen from above) on a round tile, used as the account avatar.
private struct UmbrellaAvatar: View {
    let active: Bool
    /// How the person signed in, shown as a small badge on the tile.
    var provider: SignInProvider?
    /// The intro plays once per launch, not every time the window reappears.
    private static var played = false
    @State private var tick = 0
    private static let shades: [Color] = [
        Color(red: 0.91, green: 0.94, blue: 1.0), Color(red: 0.73, green: 0.82, blue: 0.98),
        Color(red: 0.56, green: 0.68, blue: 0.95), Color(red: 0.36, green: 0.53, blue: 0.88),
        Color(red: 0.24, green: 0.45, blue: 0.89), Color(red: 0.18, green: 0.33, blue: 0.80),
        Color(red: 0.09, green: 0.21, blue: 0.50),
    ]

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = size.width * 0.32
            func vertex(_ k: Int) -> CGPoint {
                let a = -Double.pi / 2 + Double(k) * 2 * Double.pi / 7
                return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            }
            for k in 0..<7 {
                var path = Path()
                path.move(to: c)
                path.addLine(to: vertex(k))
                path.addLine(to: vertex(k + 1))
                path.closeSubpath()
                ctx.fill(path, with: .color(Self.shades[k]))
                ctx.stroke(path, with: .color(Self.shades[k]), lineWidth: 0.5)
            }
        }
        .keyframeAnimator(initialValue: Drop(), trigger: tick) { view, v in
            view.rotationEffect(.degrees(v.spin)).scaleEffect(v.scale).offset(y: v.y)
        } keyframes: { _ in
            KeyframeTrack(\.spin) {
                LinearKeyframe(900, duration: 0)
                CubicKeyframe(0, duration: 0.9)
            }
            KeyframeTrack(\.y) {
                LinearKeyframe(-70, duration: 0)
                CubicKeyframe(0, duration: 0.8)
                CubicKeyframe(-8, duration: 0.12)
                CubicKeyframe(0, duration: 0.12)
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(1.7, duration: 0)
                CubicKeyframe(1, duration: 0.8)
                CubicKeyframe(0.9, duration: 0.08)
                SpringKeyframe(1, duration: 0.2)
            }
        }
        .frame(width: 32, height: 32)
        .background(Circle().fill(PMLColor.accentText.opacity(0.12)))
        .overlay(Circle().strokeBorder(PMLColor.accentText.opacity(0.18), lineWidth: 1))
        .opacity(active ? 1 : 0.6)
        .overlay(alignment: .bottomTrailing) {
            if let symbol = badgeSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(PMLColor.ink)
                    .padding(3)
                    .background(Circle().fill(PMLColor.surfaceSunken))
                    .overlay(Circle().strokeBorder(PMLColor.accentText.opacity(0.18), lineWidth: 0.5))
                    .offset(x: 3, y: 3)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            guard !Self.played else { return }
            Self.played = true
            tick += 1
        }
    }

    private var badgeSymbol: String? {
        switch provider {
        case .apple: "apple.logo"
        case .google: "g.circle.fill"
        case .email: "envelope.fill"
        case .none: nil
        }
    }

    private struct Drop { var spin = 0.0; var y = 0.0; var scale = 1.0 }
}
