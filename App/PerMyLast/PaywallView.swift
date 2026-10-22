import PerMyLastCore
import SwiftUI

/// The paywall (FR-A15): Yearly pre-selected, Monthly second, Lifetime (bring your own key) as a quieter link.
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
                    Button("Open Settings →") { WindowCoordinator.shared.showSettings() }.buttonStyle(PMLGhostButtonStyle())
                }
            }

            VStack(spacing: 10) {
                planRow(.proYearly, title: "Pro Yearly", detail: "Best value. Runs included every month, no key needed.", badge: "Recommended")
                planRow(.proMonthly, title: "Pro Monthly", detail: "Runs included every month, no key needed.", badge: nil)
            }

            HStack {
                Button { Task { await purchases.buy(selected) } } label: {
                    Text(account.isWaitingForPurchase ? "Waiting for your purchase…" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PMLPrimaryButtonStyle())
                .disabled(!account.signedIn || !purchases.isAvailable(selected) || purchases.isBusy || account.isWaitingForPurchase)
                if account.isWaitingForPurchase || purchases.isBusy { ProgressView().controlSize(.small) }
            }

            Rectangle().fill(PMLColor.divider).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Prefer to use your own Anthropic API key?").font(PMLFont.select.weight(.bold))
                Text("Lifetime: a one-time purchase, updates for 12 months, and you pay Anthropic directly.")
                    .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                HStack {
                    Button(lifetimeTitle) { Task { await purchases.buy(.lifetime) } }
                        .disabled(!account.signedIn || !purchases.isAvailable(.lifetime) || purchases.isBusy)
                        .buttonStyle(PMLSecondaryButtonStyle())
                    if account.entitlement?.ownsLifetime == true || account.updateWindow != .ok {
                        Button("Renew updates") { Task { await purchases.buy(.lifetimeRenewal) } }
                            .disabled(!purchases.isAvailable(.lifetimeRenewal) || purchases.isBusy)
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
        case .some(.none) where account.entitlement?.trialEndsAt != nil: return "Your free trial has ended."
        default: return "Pick a plan to keep going."
        }
    }

    private var lifetimeTitle: LocalizedStringKey {
        if let price = purchases.price(.lifetime) { return "Get Lifetime · \(price)" }
        return "Get Lifetime"
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
