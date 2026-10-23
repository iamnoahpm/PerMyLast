import PerMyLastCore
import SwiftUI

/// The paywall (FR-A15): the three plans the sidebar card shows. Free (21 credits a month) is what you have by default;
/// Subscription has Yearly pre-selected; Power user (bring your own key) is a quieter section with discounted upgrades.
struct PaywallView: View {
    @Environment(AccountModel.self) private var account
    @Environment(AppModel.self) private var model
    @State private var selected = PaywallProduct.proYearly
    @State private var licenseKey = ""
    @FocusState private var licenseFocused: Bool
    private let purchases = PurchaseService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose how to use Per My Last").font(PMLFont.pageTitle)
                Text(reason).foregroundStyle(PMLColor.inkMuted)
            }

            if !AppConfig.paymentsLive {
                PMLBanner {
                    Label {
                        Text("Plans aren't open yet. You can still use your own Anthropic API key in Settings.")
                            .font(PMLFont.body).foregroundStyle(PMLColor.ink)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(PMLColor.warning)
                    }
                }
            }

            if !account.signedIn {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in first so your plan follows your account.")
                    if AppConfig.appleSignInEnabled {
                        Button("Sign in with Apple") { account.signInWithApple() }.buttonStyle(PMLSecondaryButtonStyle()).disabled(account.isBusy)
                    } else {
                        Button("Open Settings →") { WindowCoordinator.shared.showSettings() }.buttonStyle(PMLGhostButtonStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Free").font(PMLFont.select.weight(.bold))
                Text("\(AppConfig.freeCredits) credits every month. One credit is one prompt run.")
                    .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Subscription").font(PMLFont.select.weight(.bold))
                Text("Monthly or yearly. Runs included, no key needed.")
                    .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            }
            VStack(spacing: 10) {
                planRow(.proYearly, title: "Pro Yearly", detail: yearlyDetail, badge: "Recommended")
                planRow(.proMonthly, title: "Pro Monthly", detail: "Runs included every month, no key needed.", badge: nil)
            }

            HStack {
                Button { Task { await purchases.buy(selected) } } label: {
                    continueLabel.frame(maxWidth: .infinity)
                }
                .buttonStyle(PMLPrimaryButtonStyle())
                .disabled(!account.signedIn || !purchases.isAvailable(selected) || purchases.isBusy || account.isWaitingForPurchase)
                if account.isWaitingForPurchase || purchases.isBusy { ProgressView().controlSize(.small) }
            }

            Rectangle().fill(PMLColor.divider).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Power user").font(PMLFont.select.weight(.bold))
                Text("Bring your own Claude key and pay Anthropic directly. One purchase includes updates for 12 months. After that, each upgrade costs half of your last payment, and halves again each time.")
                    .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                HStack {
                    Button(lifetimeTitle) { Task { await purchases.buy(.lifetime) } }
                        .disabled(!account.signedIn || !purchases.isAvailable(.lifetime) || purchases.isBusy)
                        .buttonStyle(PMLSecondaryButtonStyle())
                    if account.entitlement?.ownsLifetime == true || account.updateWindow != .ok {
                        Button(upgradeTitle) { Task { await purchases.buy(upgradeProduct) } }
                            .disabled(!purchases.isAvailable(upgradeProduct) || purchases.isBusy)
                            .buttonStyle(PMLSecondaryButtonStyle())
                    }
                }
            }

            if purchases.channel == .direct {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Have a license key?").font(PMLFont.select.weight(.bold))
                    HStack {
                        TextField("License key", text: $licenseKey)
                            .pmlInput(focus: $licenseFocused)
                        Button("Activate") { Task { if await account.activateLicense(licenseKey) { licenseKey = "" } } }
                            .disabled(licenseKey.trimmingCharacters(in: .whitespaces).count < 8 || account.isBusy)
                            .buttonStyle(PMLSecondaryButtonStyle())
                    }
                }
            }

            HStack {
                Button("Restore purchases") { Task { await purchases.restore() } }.buttonStyle(PMLGhostButtonStyle())
                Spacer()
                Button("Close") { WindowCoordinator.shared.hidePaywall() }
                    .buttonStyle(PMLSecondaryButtonStyle())
            }

            if let text = purchases.message ?? account.message {
                Text(text).font(PMLFont.hint)
                    .foregroundStyle((purchases.message != nil ? purchases.messageIsError : account.messageIsError) ? PMLColor.danger : PMLColor.inkMuted)
            }
        }
        .padding(PMLSpace.s5)
        .frame(width: 460)
        .background(PMLColor.surface)
        .task { await purchases.loadProducts() }
        .onChange(of: account.entitlement) {
            if let plan = account.entitlement?.plan, plan.isPro || account.entitlement?.ownsLifetime == true { WindowCoordinator.shared.hidePaywall() }
        }
    }

    private var reason: LocalizedStringKey {
        switch account.entitlement?.plan {
        case .some(.free) where account.entitlement?.runsLeft == 0: return "You've used this month's free credits."
        default: return "Pick a plan to keep going."
        }
    }

    @ViewBuilder private var continueLabel: some View {
        if account.isWaitingForPurchase {
            Text("Waiting for your purchase…")
        } else if let days = purchases.freeTrialDays(selected) {
            Text("Start \(days)-day free trial")
        } else {
            Text("Continue")
        }
    }

    private var yearlyDetail: LocalizedStringKey {
        if let days = purchases.freeTrialDays(.proYearly) { return "\(days) days free, then billed yearly. Best value. Runs included, no key needed." }
        return "Best value. Runs included every month, no key needed."
    }

    private var lifetimeTitle: LocalizedStringKey {
        if let price = purchases.price(.lifetime) { return "Get Power user · \(price)" }
        return "Get Power user"
    }

    /// The upgrade the account is due: half the price of the one before, per `next_upgrade_tier` from the server.
    private var upgradeProduct: PaywallProduct { .upgrade(tier: account.entitlement?.nextUpgradeTier ?? 1) }

    private var upgradeTitle: LocalizedStringKey {
        if let price = purchases.price(upgradeProduct) { return "Upgrade updates · \(price) (half price)" }
        return "Upgrade updates (half price)"
    }

    private func planRow(_ product: PaywallProduct, title: LocalizedStringKey, detail: LocalizedStringKey, badge: LocalizedStringKey?) -> some View {
        Button { selected = product } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected == product ? "largecircle.fill.circle" : "circle").foregroundStyle(selected == product ? PMLColor.accentText : PMLColor.inkMuted)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).font(PMLFont.cardTitle).foregroundStyle(PMLColor.ink)
                        if let badge { Text(badge).font(PMLFont.badge).padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(PMLColor.accentText)
                            .background(PMLColor.accentSoft, in: Capsule()) }
                    }
                    Text(detail).font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                }
                Spacer()
                if let price = purchases.price(product) { Text(price).font(PMLFont.cardTitle).foregroundStyle(PMLColor.ink) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(selected == product ? PMLColor.accentSoft : PMLColor.surface))
            .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(selected == product ? PMLColor.accent : PMLColor.line, lineWidth: selected == product ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
