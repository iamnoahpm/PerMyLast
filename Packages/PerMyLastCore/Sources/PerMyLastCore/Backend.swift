import CryptoKit
import Foundation

// MARK: Plans

public enum PlanKind: String, Codable, Sendable {
    case none, trial, lifetime
    case proMonthly = "pro_monthly"
    case proYearly = "pro_yearly"

    public var isPro: Bool { self == .proMonthly || self == .proYearly }
}

/// Response of `GET /v1/me`: the plan the server resolved for this user.
public struct EntitlementInfo: Codable, Equatable, Sendable {
    public var plan: PlanKind
    public var trialEndsAt: Date?
    public var runsUsed: Int?
    public var runsAllowance: Int?
    public var periodEnd: Date?
    public var ownsLifetime: Bool
    public var updatesUntil: Date?

    public init(plan: PlanKind, trialEndsAt: Date? = nil, runsUsed: Int? = nil, runsAllowance: Int? = nil,
                periodEnd: Date? = nil, ownsLifetime: Bool = false, updatesUntil: Date? = nil) {
        self.plan = plan; self.trialEndsAt = trialEndsAt; self.runsUsed = runsUsed; self.runsAllowance = runsAllowance
        self.periodEnd = periodEnd; self.ownsLifetime = ownsLifetime; self.updatesUntil = updatesUntil
    }

    private enum CodingKeys: String, CodingKey {
        case plan, trialEndsAt = "trial_ends_at", runsUsed = "runs_used", runsAllowance = "runs_allowance"
        case periodEnd = "period_end", ownsLifetime = "owns_lifetime", updatesUntil = "updates_until"
    }

    public var runsLeft: Int? {
        guard let used = runsUsed, let allowance = runsAllowance else { return nil }
        return max(0, allowance - used)
    }

    /// Share of the allowance already used, 0...1 (nil when there is no allowance).
    public var usedFraction: Double? {
        guard let used = runsUsed, let allowance = runsAllowance, allowance > 0 else { return nil }
        return min(1, Double(used) / Double(allowance))
    }

    public func trialDaysLeft(now: Date = Date()) -> Int? {
        guard let end = trialEndsAt else { return nil }
        return max(0, Int((end.timeIntervalSince(now) / 86_400).rounded(.up)))
    }
}

public enum BackendCoding {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: text) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date \(text)"))
        }
        return d
    }()
}

// MARK: Which client serves a request (FR-A4)

public enum AIRoute: Equatable, Sendable {
    /// Shared key through the backend (trial, Pro).
    case proxy
    /// The user's own Anthropic key, straight to Anthropic.
    case direct
    /// Lifetime without a saved key: open key setup.
    case keySetup
    /// Nothing usable: trial over or never started.
    case paywall
    /// Backend is in use but nobody is signed in.
    case signIn
}

public enum AIClientFactory {
    /// - ownKeyNeedsLicense: PRD behaviour is `true` (a key only works with a Lifetime licence). It stays `false`
    ///   until purchases exist (Phase 4), so people who already use their own key are not locked out. While it is
    ///   `false`, a saved key is used instead of trial credits, so existing key users never spend your money.
    public static func route(signedIn: Bool, entitlement: EntitlementInfo?, hasOwnKey: Bool,
                             preferOwnKey: Bool, ownKeyNeedsLicense: Bool) -> AIRoute {
        let plan = entitlement?.plan ?? .none
        let keyIsFree = !ownKeyNeedsLicense && hasOwnKey

        guard signedIn else { return keyIsFree ? .direct : .signIn }

        switch plan {
        case .proMonthly, .proYearly:
            // Pro + Lifetime owners can switch to their own key ("Use my own API key instead").
            let mayUseKey = (entitlement?.ownsLifetime ?? false) || !ownKeyNeedsLicense
            return preferOwnKey && hasOwnKey && mayUseKey ? .direct : .proxy
        case .trial:
            return keyIsFree ? .direct : .proxy
        case .lifetime:
            return hasOwnKey ? .direct : .keySetup
        case .none:
            return keyIsFree ? .direct : .paywall
        }
    }
}

// MARK: Errors

/// An error answered by the backend: `{error: {code, message}}` plus optional details.
public struct BackendError: Error, LocalizedError, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case unauthenticated, invalidToken, invalidCode
        case noEntitlement, trialExpired, trialCreditsExhausted, quotaExhausted, byokRequired
        case trialAlreadyUsed, inputTooLarge, rateLimited, upstream, emailUnavailable, unreachable
        case unknownLicense, licenseAlreadyUsed, invalidReceipt, wrongAccount, other
    }

    public let code: String
    public let message: String
    public let status: Int
    public let retryAfter: Int?
    public let limit: Int?

    public init(code: String, message: String, status: Int = 0, retryAfter: Int? = nil, limit: Int? = nil) {
        self.code = code; self.message = message; self.status = status; self.retryAfter = retryAfter; self.limit = limit
    }

    public var errorDescription: String? { message }

    public var kind: Kind {
        switch code {
        case "unauthenticated": return .unauthenticated
        case "invalid_token": return .invalidToken
        case "invalid_code": return .invalidCode
        case "no_entitlement": return .noEntitlement
        case "trial_expired": return .trialExpired
        case "trial_credits_exhausted": return .trialCreditsExhausted
        case "quota_exhausted": return .quotaExhausted
        case "byok_required": return .byokRequired
        case "trial_already_used": return .trialAlreadyUsed
        case "input_too_large": return .inputTooLarge
        case "rate_limited": return .rateLimited
        case "upstream_error": return .upstream
        case "email_unavailable": return .emailUnavailable
        case "unreachable": return .unreachable
        case "unknown_license": return .unknownLicense
        case "license_already_used": return .licenseAlreadyUsed
        case "invalid_receipt", "unknown_product": return .invalidReceipt
        case "wrong_account": return .wrongAccount
        default: return .other
        }
    }

    /// Errors that should open the paywall (FR-A15).
    public var showsPaywall: Bool { [.noEntitlement, .trialExpired, .trialCreditsExhausted].contains(kind) }

    static func parse(data: Data, status: Int, retryAfterHeader: String? = nil) -> BackendError {
        let error = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any]
        return BackendError(
            code: error?["code"] as? String ?? "http_\(status)",
            message: error?["message"] as? String ?? "The server returned an error (\(status)).",
            status: status,
            retryAfter: (error?["retry_after"] as? Int) ?? retryAfterHeader.flatMap(Int.init),
            limit: error?["limit"] as? Int)
    }

    static func unreachable(_ error: Error) -> BackendError {
        BackendError(code: "unreachable", message: error.localizedDescription)
    }
}

// MARK: Proxy client (FR-A3)

/// Runs templates through the backend with the shared key: `POST {baseURL}/v1/run`, answered as server-sent events.
public struct ProxyClient: AIClient {
    private let baseURL: URL
    private let accessToken: String
    private let transport: any HTTPStreamTransport
    private let onRunsRemaining: (@Sendable (Int?) -> Void)?

    public init(baseURL: URL, accessToken: String, transport: any HTTPStreamTransport = URLSessionStreamTransport(),
                onRunsRemaining: (@Sendable (Int?) -> Void)? = nil) {
        self.baseURL = baseURL; self.accessToken = accessToken; self.transport = transport; self.onRunsRemaining = onRunsRemaining
    }

    public func run(templateID: String, variables: [String: String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(templateID: templateID, variables: variables, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(templateID: String, variables: [String: String],
                        into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/run"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["template_id": templateID, "variables": variables])

        let status: Int
        let lines: AsyncThrowingStream<String, Error>
        do {
            (status, lines) = try await transport.lines(for: request)
        } catch {
            throw BackendError.unreachable(error)
        }

        guard (200..<300).contains(status) else {
            var body = ""
            for try await line in lines { body += line }
            throw BackendError.parse(data: Data(body.utf8), status: status)
        }

        var event = ""
        var gotText = false
        var finished = false
        do {
            for try await line in lines {
                if line.hasPrefix("event:") { event = line.dropFirst(6).trimmingCharacters(in: .whitespaces); continue }
                guard line.hasPrefix("data:") else { continue }
                let payload = (try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8))) as? [String: Any] ?? [:]
                switch event {
                case "delta":
                    if let text = payload["text"] as? String, !text.isEmpty { gotText = true; continuation.yield(text) }
                case "done":
                    finished = true
                    onRunsRemaining?(payload["runs_remaining"] as? Int)
                case "error":
                    throw BackendError(code: payload["code"] as? String ?? "upstream_error",
                                       message: payload["message"] as? String ?? "The answer was cut short.", status: status)
                default: break
                }
            }
        } catch let error as BackendError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw BackendError.unreachable(error)
        }
        if !finished && !gotText { throw BackendError(code: "upstream_error", message: "No answer came back. Try again.", status: status) }
    }
}

// MARK: Account calls

public struct AuthSession: Codable, Equatable, Sendable {
    public var userID: String
    public var accessToken: String
    public var refreshToken: String
    public var accessExpiresAt: Date

    public init(userID: String, accessToken: String, refreshToken: String, accessExpiresAt: Date) {
        self.userID = userID; self.accessToken = accessToken; self.refreshToken = refreshToken; self.accessExpiresAt = accessExpiresAt
    }

    /// True when the access token is expired or about to be.
    public func needsRefresh(now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        accessExpiresAt.timeIntervalSince(now) < margin
    }
}

public struct TrialInfo: Equatable, Sendable {
    public var plan: PlanKind
    public var trialEndsAt: Date?
    public var runsAllowance: Int
}

/// Sign-in, plan and trial calls to the backend.
public struct BackendClient: Sendable {
    public let baseURL: URL
    private let transport: any HTTPTransport

    public init(baseURL: URL, transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL; self.transport = transport
    }

    public func requestEmailCode(email: String) async throws {
        _ = try await send("v1/auth/email/request", body: ["email": email])
    }

    public func verifyEmailCode(email: String, code: String, now: Date = Date()) async throws -> AuthSession {
        try session(try await send("v1/auth/email/verify", body: ["email": email, "code": code]), now: now)
    }

    public func signIn(provider: String, idToken: String, nonce: String? = nil, now: Date = Date()) async throws -> AuthSession {
        var body = ["id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        return try session(try await send("v1/auth/\(provider)", body: body), now: now)
    }

    public func refresh(refreshToken: String, now: Date = Date()) async throws -> AuthSession {
        try session(try await send("v1/auth/refresh", body: ["refresh_token": refreshToken]), now: now)
    }

    public func me(accessToken: String) async throws -> EntitlementInfo {
        let data = try await send("v1/me", method: "GET", token: accessToken)
        return try BackendCoding.decoder.decode(EntitlementInfo.self, from: data)
    }

    public func startTrial(accessToken: String, installIDHash: String) async throws -> TrialInfo {
        let data = try await send("v1/trial/start", body: ["install_id_hash": installIDHash], token: accessToken)
        struct Wire: Decodable { var plan: PlanKind; var trial_ends_at: Date?; var runs_allowance: Int }
        let w = try BackendCoding.decoder.decode(Wire.self, from: data)
        return TrialInfo(plan: w.plan, trialEndsAt: w.trial_ends_at, runsAllowance: w.runs_allowance)
    }

    /// Links a Lemon Squeezy licence key to this account (for people who bought before signing in).
    public func activateLicense(accessToken: String, licenseKey: String) async throws -> EntitlementInfo {
        let data = try await send("v1/license/activate", body: ["license_key": licenseKey], token: accessToken)
        return try BackendCoding.decoder.decode(EntitlementInfo.self, from: data)
    }

    /// Sends an Apple-signed StoreKit transaction after a purchase, and again on "Restore purchases".
    public func submitStoreKitTransaction(accessToken: String, signedTransaction: String) async throws -> EntitlementInfo {
        let data = try await send("v1/purchases/storekit", body: ["signed_transaction": signedTransaction], token: accessToken)
        return try BackendCoding.decoder.decode(EntitlementInfo.self, from: data)
    }

    private func session(_ data: Data, now: Date) throws -> AuthSession {
        struct Wire: Decodable { var user_id: String; var access_token: String; var refresh_token: String; var expires_in: Int }
        let w = try JSONDecoder().decode(Wire.self, from: data)
        return AuthSession(userID: w.user_id, accessToken: w.access_token, refreshToken: w.refresh_token,
                           accessExpiresAt: now.addingTimeInterval(TimeInterval(w.expires_in)))
    }

    private func send(_ path: String, method: String = "POST", body: [String: String]? = nil, token: String? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw BackendError.unreachable(error)
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw BackendError.parse(data: data, status: status, retryAfterHeader: http?.value(forHTTPHeaderField: "Retry-After"))
        }
        return data
    }
}

/// SHA-256 of the install id, as the backend expects (lowercase hex).
public func installIDHash(_ installID: String) -> String {
    sha256Hex(Data(installID.utf8))
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// MARK: Purchases

/// What the paywall sells (PRD section 7).
public enum PaywallProduct: String, CaseIterable, Sendable {
    case proYearly, proMonthly, lifetime, lifetimeRenewal

    /// StoreKit product id, the same ids as in App Store Connect.
    public var storeKitID: String {
        switch self {
        case .proYearly: return "pro_yearly"
        case .proMonthly: return "pro_monthly"
        case .lifetime: return "lifetime_byok"
        case .lifetimeRenewal: return "lifetime_renewal"
        }
    }

    public init?(storeKitID: String) {
        guard let p = Self.allCases.first(where: { $0.storeKitID == storeKitID }) else { return nil }
        self = p
    }

    public var isSubscription: Bool { self == .proYearly || self == .proMonthly }
}

/// Lemon Squeezy checkout link for the direct build. Only the random account id travels in the URL (it lets the
/// webhook credit the right account); no email or other personal data.
public func checkoutURL(base: URL, userID: String) -> URL {
    var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
    var items = parts.queryItems ?? []
    items.removeAll { $0.name == "checkout[custom][user_id]" }
    items.append(URLQueryItem(name: "checkout[custom][user_id]", value: userID))
    parts.queryItems = items
    return parts.url ?? base
}
