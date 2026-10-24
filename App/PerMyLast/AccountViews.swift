import PerMyLastCore
import SwiftUI

/// Settings → General → Account: sign in, plan meter, sign out. Only shown when a backend is configured.
struct AccountSection: View {
    @Environment(AppModel.self) private var model
    @Environment(AccountModel.self) private var account

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
        return account.planTitle
    }

    private var subtitle: String? {
        if account.signedIn { return account.usageText }
        return account.isConfigured ? L("Sign in to save your setup") : nil
    }

    var body: some View {
        Button { WindowCoordinator.shared.showSettings() } label: {
            HStack(spacing: PMLSpace.s2) {
                Image(systemName: account.signedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(account.signedIn ? PMLColor.accentText : PMLColor.inkMuted)
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
