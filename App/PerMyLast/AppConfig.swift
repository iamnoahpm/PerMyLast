import Foundation
import PerMyLastCore

/// App-side config (PRD section 11): one place, no values scattered through the code.
enum AppConfig {
    /// Where the backend Worker lives, e.g. https://permylast-api.<you>.workers.dev. Leave empty until it is
    /// deployed: with no backend the app behaves as before (your own key only, no sign-in).
    /// For development, set PML_BACKEND_URL (use http://127.0.0.1:8787 for `wrangler dev`).
    private static let backendURLString = "https://permylast-api.iamnoahpm.workers.dev"

    static var backendURL: URL? {
        let override = ProcessInfo.processInfo.environment["PML_BACKEND_URL"] ?? UserDefaults.standard.string(forKey: "backendURL")
        let text = (override?.isEmpty == false ? override : nil) ?? backendURLString
        return text.isEmpty ? nil : URL(string: text)
    }

    /// Flip to `true` at launch, once the App Store products exist and a sandbox purchase has worked end to end. Until then nothing can be bought, so people who already use their own key
    /// keep using it, and the paywall says plans are not open yet.
    static let paymentsLiveInRelease = false

    /// `PML_PAYMENTS_LIVE=1` switches payments on for a test run only (App Store sandbox) without
    /// changing what ships. Remember it also makes your own key require a Lifetime licence in that run.
    static var paymentsLive: Bool {
        paymentsLiveInRelease || ProcessInfo.processInfo.environment["PML_PAYMENTS_LIVE"] == "1"
    }

    /// PRD behaviour: an own Anthropic key needs a Lifetime licence.
    static var ownKeyNeedsLicense: Bool { paymentsLive }

    /// Sign in with Apple needs the app signed with a real team and the capability enabled in Xcode for the release
    /// target (see backend/README). The app signs in with Apple only: one tap, no email codes.
    static let appleSignInEnabled = true
    static let emailSignInEnabled = false
    /// Google OAuth client id (iOS/desktop type). Empty hides Google sign-in.
    static let googleClientID = ""
    static var googleSignInEnabled: Bool { false }

    /// FR-P7: the date this build was released. Update it for every release. A Lifetime licence whose 12 months of updates
    /// ended before this date cannot use the build (it shows "Renew updates to use this version").
    static let releaseDate: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 23
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c) ?? Date()
    }()
    /// Set to true for a compatibility-fix build, which Lifetime users may keep using for 12 months longer.
    static let isPatchBuild = false

    /// Credits the Free plan renews with every month, as the plans card and paywall say it. Keep in step with
    /// FREE_MONTHLY_CREDITS in backend/config.ts.
    static let freeCredits = 21

    /// FR-A14: warn at this share of the allowance.
    static let warnAtFraction = 0.8
}
