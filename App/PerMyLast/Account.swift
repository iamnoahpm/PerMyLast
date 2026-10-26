import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import PerMyLastCore

/// Sign-in, the trial and the usage meter (FR-A7, A8, A9, A13, A14). The server is the source of truth for the
/// plan; this keeps the last answer only to display it.
@MainActor
@Observable
final class AccountModel {
    static let shared = AccountModel()

    // MARK: State
    private(set) var session: AuthSession?
    private(set) var entitlement: EntitlementInfo?
    /// When the server last confirmed the plan (NFR-11).
    private(set) var entitlementFetchedAt: Date?
    var useOwnKey: Bool { didSet { UserDefaults.standard.set(useOwnKey, forKey: "useOwnKeyInsteadOfPro") } }

    // Email sign-in form
    enum EmailStep { case enterEmail, enterCode }
    var email = ""
    var code = ""
    var emailStep = EmailStep.enterEmail
    var isBusy = false
    var message: String?
    var messageIsError = false

    /// A one-time warning to show in the popup (FR-A14).
    var warning: String?

    private let sessionStore: any APIKeyStore = KeychainAPIKeyStore(service: "app.permylast.session")
    private let installStore: any APIKeyStore = KeychainAPIKeyStore(service: "app.permylast.install-id")
    private var refreshTask: Task<AuthSession, Error>?

    private init() {
        useOwnKey = UserDefaults.standard.bool(forKey: "useOwnKeyInsteadOfPro")
        if let json = try? sessionStore.load(), let data = json.data(using: .utf8) {
            session = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
        if let cached = Persistence.load("cachedEntitlement", as: EntitlementInfo.self) { entitlement = cached }
        entitlementFetchedAt = UserDefaults.standard.object(forKey: "entitlementFetchedAt") as? Date
    }

    var backend: BackendClient? { AppConfig.backendURL.map { BackendClient(baseURL: $0) } }
    var isConfigured: Bool { AppConfig.backendURL != nil }
    var signedIn: Bool { session != nil }
    /// The address used for email sign-in, kept so the rail can say who is signed in. Apple/Google sign-ins leave it empty.
    private(set) var signedInEmail: String? = UserDefaults.standard.string(forKey: "signedInEmail")

    // MARK: Routing (FR-A4)

    func route(hasOwnKey: Bool) -> AIRoute {
        guard isConfigured else { return .direct }
        return AIClientFactory.route(signedIn: signedIn, entitlement: entitlement, hasOwnKey: hasOwnKey,
                                     preferOwnKey: useOwnKey, ownKeyNeedsLicense: AppConfig.ownKeyNeedsLicense,
                                     entitlementIsStale: !OfflinePolicy.lifetimeIsFresh(fetchedAt: entitlementFetchedAt))
    }

    /// FR-P7: whether this build is covered by the Lifetime licence. Only enforced once payments are live.
    var updateWindow: UpdateWindow.Status {
        guard AppConfig.paymentsLive, signedIn, let me = entitlement else { return .ok }
        return UpdateWindow.status(plan: me.plan, updatesUntil: me.updatesUntil, buildDate: AppConfig.releaseDate, isPatchBuild: AppConfig.isPatchBuild)
    }

    // MARK: Session

    /// A valid access token, refreshing quietly when it is about to expire.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = session else { throw BackendError(code: "unauthenticated", message: L("Sign in to continue.")) }
        if !forceRefresh && !current.needsRefresh() { return current.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let backend else { throw BackendError(code: "unauthenticated", message: L("Sign in to continue.")) }
        let task = Task { try await backend.refresh(refreshToken: current.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            store(fresh)
            return fresh.accessToken
        } catch let error as BackendError where error.kind == .invalidToken || error.kind == .unauthenticated {
            signOut()   // the refresh token is no good any more
            throw BackendError(code: "unauthenticated", message: L("Your session ended. Sign in again."))
        }
    }

    private func store(_ s: AuthSession) {
        session = s
        if let data = try? JSONEncoder().encode(s), let text = String(data: data, encoding: .utf8) { try? sessionStore.save(text) }
    }

    func signOut() {
        session = nil
        entitlement = nil
        warning = nil
        signedInEmail = nil
        UserDefaults.standard.removeObject(forKey: "signedInEmail")
        try? sessionStore.delete()
        UserDefaults.standard.removeObject(forKey: "cachedEntitlement")
        UserDefaults.standard.removeObject(forKey: "entitlementFetchedAt")
        entitlementFetchedAt = nil
        emailStep = .enterEmail
        code = ""
    }

    /// Random per-install id kept in the Keychain so it survives a reinstall (FR-A8).
    func installID() -> String {
        if let existing = try? installStore.load(), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString
        try? installStore.save(fresh)
        return fresh
    }

    // MARK: Email code sign-in

    func sendCode() async {
        guard let backend else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@") else { show(L("Enter your email address."), error: true); return }
        isBusy = true; defer { isBusy = false }
        do {
            try await backend.requestEmailCode(email: address)
            emailStep = .enterCode
            code = ""
            show(L("We sent a 6-digit code to \(address)."), error: false)
        } catch let error as BackendError {
            show(friendly(error), error: true)
        } catch { show(error.localizedDescription, error: true) }
    }

    func verifyCode() async {
        guard let backend else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
            let s = try await backend.verifyEmailCode(email: address, code: code.trimmingCharacters(in: .whitespaces))
            signedInEmail = address
            UserDefaults.standard.set(address, forKey: "signedInEmail")
            await didSignIn(s)
        } catch let error as BackendError {
            show(friendly(error), error: true)
        } catch { show(error.localizedDescription, error: true) }
    }

    func useDifferentEmail() { emailStep = .enterEmail; code = ""; message = nil }

    // MARK: Apple and Google (FR-A7). Hidden until configured in AppConfig; see backend/README.

    private var appleDelegate: AppleSignInDelegate?

    func signInWithApple() {
        guard let backend else { return }
        let rawNonce = UUID().uuidString + UUID().uuidString
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
        let delegate = AppleSignInDelegate { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                self.appleDelegate = nil
                switch result {
                case .success(let (token, code)):
                    self.isBusy = true; defer { self.isBusy = false }
                    do { await self.didSignIn(try await backend.signIn(provider: "apple", idToken: token, nonce: rawNonce, authorizationCode: code)) }
                    catch { self.show((error as? BackendError).map(self.friendly) ?? error.localizedDescription, error: true) }
                case .failure(let error): self.show(error.localizedDescription, error: true)
                }
            }
        }
        appleDelegate = delegate
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.performRequests()
    }

    private var webSession: ASWebAuthenticationSession?
    private let webContext = WebAuthContext()

    /// Google sign-in with the system browser sheet and PKCE; no SDK needed.
    func signInWithGoogle() async {
        guard let backend, !AppConfig.googleClientID.isEmpty else { return }
        let id = AppConfig.googleClientID
        let scheme = "com.googleusercontent.apps." + (id.split(separator: ".").first.map(String.init) ?? id)
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [.init(name: "client_id", value: id), .init(name: "redirect_uri", value: redirect),
                            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email"),
                            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")]
        isBusy = true; defer { isBusy = false }
        do {
            let callback: URL = try await withCheckedThrowingContinuation { cont in
                let s = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: scheme) { url, error in
                    if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? URLError(.cancelled)) }
                }
                s.presentationContextProvider = webContext
                webSession = s
                s.start()
            }
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else { return }
            var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = "client_id=\(id)&code=\(code)&code_verifier=\(verifier)&grant_type=authorization_code&redirect_uri=\(redirect)".data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let idToken = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["id_token"] as? String else {
                show(L("Google sign-in didn't complete."), error: true); return
            }
            await didSignIn(try await backend.signIn(provider: "google", idToken: idToken))
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // closed by the user
        } catch let error as BackendError {
            show(friendly(error), error: true)
        } catch { show(error.localizedDescription, error: true) }
    }

    // MARK: After sign-in

    private func didSignIn(_ s: AuthSession) async {
        store(s)
        message = nil
        email = ""; code = ""; emailStep = .enterEmail
        await claimFreeCreditsIfNeeded()
        await refreshEntitlement()
    }

    /// FR-A9: the Free plan's monthly credits start by themselves on first sign-in. Safe to repeat; the server gives one
    /// account per Mac its free credits.
    func claimFreeCreditsIfNeeded() async {
        guard let backend, session != nil else { return }
        do {
            let token = try await validAccessToken()
            _ = try await backend.claimFreeCredits(accessToken: token, installIDHash: installIDHash(installID()))
        } catch let error as BackendError where error.kind == .installAlreadyUsed {
            show(L("Free credits have already been claimed on this Mac by another account."), error: true)
        } catch {
            // Not fatal: the next refresh or launch tries again.
        }
    }

    func refreshEntitlement() async {
        guard let backend, session != nil else { return }
        do {
            let me = try await backend.me(accessToken: try await validAccessToken())
            apply(me)
        } catch {
            // Offline or a server hiccup: keep showing the last known plan.
        }
    }

    /// `verified` is true when the server just told us this (not when we only adjusted the count after a run).
    func apply(_ me: EntitlementInfo, verified: Bool = true) {
        entitlement = me
        Persistence.save(me, key: "cachedEntitlement")
        if verified {
            entitlementFetchedAt = Date()
            UserDefaults.standard.set(entitlementFetchedAt, forKey: "entitlementFetchedAt")
        }
        updateWarning()
    }

    /// Updates the meter right after a run, without another request.
    func noteRunsRemaining(_ remaining: Int?) {
        guard var me = entitlement, let remaining, let allowance = me.runsAllowance else { return }
        me.runsUsed = max(0, allowance - remaining)
        apply(me, verified: false)
    }

    // MARK: Purchases (Phase 4)

    /// Sends an Apple-signed transaction to the backend, which verifies it and grants the plan (FR-P1, P2).
    func submitStoreKit(jws: String) async throws {
        guard let backend else { throw BackendError(code: "unauthenticated", message: L("Sign in to continue.")) }
        let me = try await backend.submitStoreKitTransaction(accessToken: try await validAccessToken(), signedTransaction: jws)
        apply(me)
    }

    /// Deletes the account on the server, then signs out here. The purchases stay with the Apple ID, but the plan does not
    /// carry over to a new account, so the confirmation says so.
    func deleteAccount() async -> Bool {
        guard let backend, signedIn else { return false }
        isBusy = true; defer { isBusy = false }
        do {
            try await backend.deleteAccount(accessToken: try await validAccessToken())
            signOut()
            show(L("Your account was deleted."), error: false)
            return true
        } catch let error as BackendError {
            show(friendly(error), error: true)
        } catch { show(error.localizedDescription, error: true) }
        return false
    }

    // MARK: Meter text (FR-A13) and warnings (FR-A14)

    var meterText: String? {
        guard isConfigured else { return nil }
        guard signedIn else { return nil }
        guard let me = entitlement else { return nil }
        switch me.plan {
        case .free:
            guard let left = me.runsLeft, let allowance = me.runsAllowance else { return nil }
            if let end = me.periodEnd {
                return L("Free: \(left) of \(allowance) credits left · resets \(end.formatted(date: .abbreviated, time: .omitted))")
            }
            return L("Free: \(left) of \(allowance) credits left")
        case .proMonthly, .proYearly:
            guard let used = me.runsUsed, let allowance = me.runsAllowance else { return nil }
            if let end = me.periodEnd {
                return L("Pro: \(used) / \(allowance) runs · resets \(end.formatted(date: .abbreviated, time: .omitted))")
            }
            return L("Pro: \(used) / \(allowance) runs")
        case .lifetime:
            return L("Using your Anthropic key")
        case .none:
            return nil
        }
    }

    /// The plan's name, for the account row's title.
    var planTitle: String {
        guard let plan = entitlement?.plan else { return L("Signed in") }
        switch plan {
        case .free: return L("Free plan")
        case .proMonthly: return L("Pro · monthly")
        case .proYearly: return L("Pro · yearly")
        case .lifetime: return L("Lifetime")
        case .none: return L("Signed in")
        }
    }

    /// `meterText` without the plan's name, which the account row already shows as its title.
    var usageText: String? {
        guard isConfigured, signedIn, let me = entitlement else { return nil }
        let reset = me.periodEnd.map { $0.formatted(date: .abbreviated, time: .omitted) }
        switch me.plan {
        case .free:
            guard let left = me.runsLeft, let allowance = me.runsAllowance else { return nil }
            if let reset { return L("\(left) of \(allowance) credits left · resets \(reset)") }
            return L("\(left) of \(allowance) credits left")
        case .proMonthly, .proYearly:
            guard let used = me.runsUsed, let allowance = me.runsAllowance else { return nil }
            if let reset { return L("\(used) / \(allowance) runs · resets \(reset)") }
            return L("\(used) / \(allowance) runs")
        case .lifetime:
            return L("Using your Anthropic key")
        case .none:
            return nil
        }
    }

    /// Shows each warning once per period, at 80% of the allowance.
    private func updateWarning() {
        guard let me = entitlement, me.plan == .free || me.plan.isPro else { return }
        let defaults = UserDefaults.standard
        if let fraction = me.usedFraction, fraction >= AppConfig.warnAtFraction, let left = me.runsLeft {
            let key = "warned80-\(me.plan.rawValue)-\(Int(me.periodEnd?.timeIntervalSince1970 ?? 0))"
            if !defaults.bool(forKey: key) {
                defaults.set(true, forKey: key)
                warning = me.plan == .free
                    ? L("You have \(left) free credits left this month.")
                    : L("You've used 80% of this month's runs (\(left) left).")
                return
            }
        }
    }

    // MARK: Messages

    private func show(_ text: String, error: Bool) { message = text; messageIsError = error }

    /// A readable message for what the backend said.
    func friendly(_ error: BackendError) -> String {
        switch error.kind {
        case .invalidCode: return L("That code is wrong or has expired.")
        case .invalidToken: return L("That sign-in couldn't be verified.")
        case .emailUnavailable: return L("We couldn't send the email. Try again later.")
        case .installAlreadyUsed: return L("Free credits have already been claimed on this Mac by another account.")
        case .rateLimited: return L("Too many requests. Try again in \(error.retryAfter ?? 10) seconds.")
        case .unreachable: return L("You're offline. Connect to the internet to use your plan.")
        default: return error.message
        }
    }
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let done: (Result<(token: String, code: String?), Error>) -> Void
    init(done: @escaping (Result<(token: String, code: String?), Error>) -> Void) { self.done = done }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
           let data = cred.identityToken, let token = String(data: data, encoding: .utf8) {
            done(.success((token, cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) })))
        } else {
            done(.failure(URLError(.badServerResponse)))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { done(.failure(error)) }
}

private final class WebAuthContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
