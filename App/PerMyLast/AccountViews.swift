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
            .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { _ = await self.account.deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently erases your account, plan and usage from our servers. It can't be undone. It does not cancel an App Store subscription: cancel it in your Apple ID settings first, or you'll keep being billed.")
            }
    }
}

/// Footer text: the usage meter (FR-A13).
struct UsageMeterLabel: View {
    @Environment(AccountModel.self) private var account

    var body: some View {
        if let text = account.meterText {
            Text(text).foregroundStyle(PMLColor.inkMuted)
        }
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
                UmbrellaAvatar(active: account.signedIn)
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
        .onAppear {
            guard !Self.played else { return }
            Self.played = true
            tick += 1
        }
    }

    private struct Drop { var spin = 0.0; var y = 0.0; var scale = 1.0 }
}
