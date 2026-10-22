import PerMyLastCore
import SwiftUI

/// The paywall (FR-A15): Yearly pre-selected, Monthly second, Lifetime (bring your own key) as a quieter link.
struct PaywallView: View {
    @Environment(AccountModel.self) private var account
    @Environment(AppModel.self) private var model
    @State private var selected = PaywallProduct.proYearly
    @State private var licenseKey = ""
    private let purchases = PurchaseService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose how to use Per My Last").font(.title2.bold())
                Text(reason).foregroundStyle(.secondary)
            }

            if !AppConfig.paymentsLive {
                Label("Plans aren't open yet. You can still use your own Anthropic API key in Settings.", systemImage: "info.circle")
                    .font(.callout).padding(10)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            if !account.signedIn {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in first so your plan follows your account.")
                    Button("Open Settings →") { WindowCoordinator.shared.showSettings() }.buttonStyle(.link)
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
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!account.signedIn || !purchases.isAvailable(selected) || purchases.isBusy || account.isWaitingForPurchase)
                if account.isWaitingForPurchase || purchases.isBusy { ProgressView().controlSize(.small) }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Prefer to use your own Anthropic API key?").font(.callout.weight(.semibold))
                Text("Lifetime: a one-time purchase, updates for 12 months, and you pay Anthropic directly.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(lifetimeTitle) { Task { await purchases.buy(.lifetime) } }
                        .disabled(!account.signedIn || !purchases.isAvailable(.lifetime) || purchases.isBusy)
                    if account.entitlement?.ownsLifetime == true || account.updateWindow != .ok {
                        Button("Renew updates") { Task { await purchases.buy(.lifetimeRenewal) } }
                            .disabled(!purchases.isAvailable(.lifetimeRenewal) || purchases.isBusy)
                    }
                }
            }

            if purchases.channel == .direct {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Have a license key?").font(.callout.weight(.semibold))
                    HStack {
                        TextField("License key", text: $licenseKey)
                        Button("Activate") { Task { if await account.activateLicense(licenseKey) { licenseKey = "" } } }
                            .disabled(licenseKey.trimmingCharacters(in: .whitespaces).count < 8 || account.isBusy)
                    }
                }
            }

            HStack {
                Button("Restore purchases") { Task { await purchases.restore() } }.buttonStyle(.link)
                Spacer()
                Button("Close") { WindowCoordinator.shared.hidePaywall() }
            }

            if let text = purchases.message ?? account.message {
                Text(text).font(.caption)
                    .foregroundStyle((purchases.message != nil ? purchases.messageIsError : account.messageIsError) ? Color.red : Color.secondary)
            }
        }
        .padding(24)
        .frame(width: 460)
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
                Image(systemName: selected == product ? "largecircle.fill.circle" : "circle").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).font(.headline)
                        if let badge { Text(badge).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18), in: Capsule()) }
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let price = purchases.price(product) { Text(price).font(.headline) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(selected == product ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected == product ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
