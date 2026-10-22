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
        Text("Sign in to start your free trial.").foregroundStyle(PMLColor.inkMuted)
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
        if AppConfig.appleSignInEnabled || !AppConfig.googleClientID.isEmpty {
            HStack {
                if AppConfig.appleSignInEnabled { Button("Sign in with Apple") { self.account.signInWithApple() } }
                if !AppConfig.googleClientID.isEmpty { Button("Sign in with Google") { Task { await self.account.signInWithGoogle() } } }
            }
            .disabled(self.account.isBusy)
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
