import Foundation
import PerMyLastCore

/// App-side config (PRD section 11): one place, no values scattered through the code.
enum AppConfig {
    /// Where the backend Worker lives, e.g. https://permylast-api.<you>.workers.dev. Leave empty until it is
    /// deployed: with no backend the app behaves as before (your own key only, no sign-in).
    /// For development, set PML_BACKEND_URL (use http://127.0.0.1:8787 for `wrangler dev`).
    private static let backendURLString = ""

    static var backendURL: URL? {
        let override = ProcessInfo.processInfo.environment["PML_BACKEND_URL"] ?? UserDefaults.standard.string(forKey: "backendURL")
        let text = (override?.isEmpty == false ? override : nil) ?? backendURLString
        return text.isEmpty ? nil : URL(string: text)
    }

    /// Flip to `true` at launch, once the App Store products and Lemon Squeezy checkout links below exist and a test
    /// purchase has worked end to end. Until then nothing can be bought, so people who already use their own key
    /// keep using it, and the paywall says plans are not open yet.
    static let paymentsLive = false

    /// PRD behaviour: an own Anthropic key needs a Lifetime licence.
    static var ownKeyNeedsLicense: Bool { paymentsLive }

    /// Which store this build sells through. The Mac App Store build must use StoreKit only (App Store rules); the
    /// direct build sells through Lemon Squeezy only. Override with PML_CHANNEL=appstore|direct for testing.
    enum Channel { case appStore, direct }
    static var channel: Channel {
        switch ProcessInfo.processInfo.environment["PML_CHANNEL"] {
        case "appstore": return .appStore
        case "direct": return .direct
        default:
            let receipt = Bundle.main.appStoreReceiptURL
            return receipt.map { FileManager.default.fileExists(atPath: $0.path) } == true ? .appStore : .direct
        }
    }

    /// Lemon Squeezy checkout links (direct build). Create the products in Lemon Squeezy, then paste each product's
    /// "Share" checkout link here. Empty means that product cannot be bought yet.
    static let checkoutLinks: [PaywallProduct: String] = [
        .proYearly: "", .proMonthly: "", .lifetime: "", .lifetimeRenewal: "",
    ]

    /// Sign in with Apple needs the app signed with a real team and the capability enabled (see backend/README).
    static let appleSignInEnabled = false
    /// Google OAuth client id (iOS/desktop type). Empty hides Google sign-in.
    static let googleClientID = ""

    /// FR-P7: the date this build was released. Update it for every release. A Lifetime licence whose 12 months of updates
    /// ended before this date cannot use the build (it shows "Renew updates to use this version").
    static let releaseDate: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 22
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c) ?? Date()
    }()
    /// Set to true for a compatibility-fix build, which Lifetime users may keep using for 12 months longer.
    static let isPatchBuild = false
    /// Where Lifetime users can download the last build their licence covers. Empty hides the link.
    static let lastEligibleDownloadURL = ""

    /// FR-A14: warn at this share of the allowance, and this many days before the trial ends.
    static let warnAtFraction = 0.8
    static let warnDaysBeforeTrialEnds = 3
}
