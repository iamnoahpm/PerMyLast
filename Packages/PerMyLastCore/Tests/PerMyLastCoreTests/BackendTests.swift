import Foundation
import Testing
@testable import PerMyLastCore

private final class FakeStream: HTTPStreamTransport, @unchecked Sendable {
    var status = 200
    var lines: [String] = []
    var error: Error?
    private(set) var lastRequest: URLRequest?
    func lines(for request: URLRequest) async throws -> (statusCode: Int, lines: AsyncThrowingStream<String, Error>) {
        lastRequest = request
        if let error { throw error }
        let lines = self.lines
        return (status, AsyncThrowingStream { c in for l in lines { c.yield(l) }; c.finish() })
    }
}

private final class FakeHTTP: HTTPTransport, @unchecked Sendable {
    var status = 200
    var body = Data()
    var headers: [String: String] = [:]
    var error: Error?
    private(set) var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if let error { throw error }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

private func collect(_ s: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var out: [String] = []
    for try await d in s { out.append(d) }
    return out
}

private let base = URL(string: "https://api.example.com")!

@Suite("ProxyClient")
struct ProxyClientTests {
    @Test func postsTheTemplateWithTheUsersTokenAndStreamsDeltas() async throws {
        let t = FakeStream()
        t.lines = ["event: delta", #"data: {"text":"Hel"}"#, "", "event: delta", #"data: {"text":"lo"}"#, "", "event: done", #"data: {"runs_remaining":41}"#]
        let box = RunsBox()
        let client = ProxyClient(baseURL: base, accessToken: "tok", transport: t, onRunsRemaining: { box.value = $0 })
        let out = try await collect(client.run(templateID: "text.process", variables: ["content": "hi"]))
        #expect(out == ["Hel", "lo"])
        #expect(box.value == 41)
        let r = try #require(t.lastRequest)
        #expect(r.url?.absoluteString == "https://api.example.com/v1/run")
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let raw = try #require(r.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(body["template_id"] as? String == "text.process")
        #expect((body["variables"] as? [String: String]) == ["content": "hi"])
        #expect(body["system"] == nil && body["model"] == nil)   // the server decides those
    }

    @Test func mapsServerErrorCodes() async {
        for (status, code, kind) in [(402, "free_credits_exhausted", BackendError.Kind.freeCreditsExhausted),
                                     (402, "no_entitlement", .noEntitlement), (402, "quota_exhausted", .quotaExhausted),
                                     (402, "byok_required", .byokRequired), (401, "unauthenticated", .unauthenticated),
                                     (413, "input_too_large", .inputTooLarge), (502, "upstream_error", .upstream)] {
            let t = FakeStream()
            t.status = status
            t.lines = [#"{"error":{"code":"\#(code)","message":"msg","limit":12000}}"#]
            do {
                _ = try await collect(ProxyClient(baseURL: base, accessToken: "t", transport: t).run(templateID: "x", variables: [:]))
                Issue.record("expected an error for \(code)")
            } catch let e as BackendError {
                #expect(e.kind == kind && e.status == status && e.message == "msg")
            } catch { Issue.record("wrong error \(error)") }
        }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let t = FakeStream()
        t.status = 429
        t.lines = [#"{"error":{"code":"rate_limited","message":"slow down","retry_after":12}}"#]
        do {
            _ = try await collect(ProxyClient(baseURL: base, accessToken: "t", transport: t).run(templateID: "x", variables: [:]))
            Issue.record("expected an error")
        } catch let e as BackendError { #expect(e.kind == .rateLimited && e.retryAfter == 12) } catch {}
    }

    @Test func paywallCodesAreFlagged() {
        #expect(BackendError(code: "free_credits_exhausted", message: "").showsPaywall)
        #expect(BackendError(code: "no_entitlement", message: "").showsPaywall)
        #expect(!BackendError(code: "quota_exhausted", message: "").showsPaywall)
        #expect(!BackendError(code: "byok_required", message: "").showsPaywall)
    }

    @Test func anErrorEventMidStreamKeepsTheTextAlreadyShown() async {
        let t = FakeStream()
        t.lines = ["event: delta", #"data: {"text":"Par"}"#, "event: error", #"data: {"code":"upstream_error","message":"The answer was cut short."}"#]
        var got: [String] = []
        do {
            for try await d in ProxyClient(baseURL: base, accessToken: "t", transport: t).run(templateID: "x", variables: [:]) { got.append(d) }
            Issue.record("expected an error")
        } catch let e as BackendError { #expect(e.kind == .upstream) } catch {}
        #expect(got == ["Par"])
    }

    @Test func aStreamWithNothingInItIsAnError() async {
        let t = FakeStream()
        t.lines = []
        do {
            _ = try await collect(ProxyClient(baseURL: base, accessToken: "t", transport: t).run(templateID: "x", variables: [:]))
            Issue.record("expected an error")
        } catch let e as BackendError { #expect(e.kind == .upstream) } catch {}
    }

    @Test func offlineIsReportedAsUnreachable() async {
        let t = FakeStream()
        t.error = URLError(.notConnectedToInternet)
        do {
            _ = try await collect(ProxyClient(baseURL: base, accessToken: "t", transport: t).run(templateID: "x", variables: [:]))
            Issue.record("expected an error")
        } catch let e as BackendError { #expect(e.kind == .unreachable) } catch {}
    }
}

final class RunsBox: @unchecked Sendable { var value: Int? }

@Suite("AIClientFactory")
struct AIClientFactoryTests {
    private func e(_ plan: PlanKind, lifetime: Bool = false) -> EntitlementInfo { EntitlementInfo(plan: plan, ownsLifetime: lifetime) }
    private func route(_ ent: EntitlementInfo?, signedIn: Bool = true, key: Bool = false, prefer: Bool = false, license: Bool = true) -> AIRoute {
        AIClientFactory.route(signedIn: signedIn, entitlement: ent, hasOwnKey: key, preferOwnKey: prefer, ownKeyNeedsLicense: license)
    }

    @Test func followsTheRoutingTableOfThePRD() {
        #expect(route(e(.free)) == .proxy)
        #expect(route(e(.proMonthly)) == .proxy)
        #expect(route(e(.proYearly), key: true) == .proxy)
        #expect(route(e(.lifetime), key: true) == .direct)
        #expect(route(e(.lifetime), key: false) == .keySetup)
        #expect(route(e(.none)) == .paywall)
        #expect(route(nil, key: true) == .paywall)          // a key alone is not a licence
        #expect(route(nil, signedIn: false) == .signIn)
    }

    @Test func proPlusLifetimeCanSwitchToTheirOwnKey() {
        #expect(route(e(.proYearly, lifetime: true), key: true, prefer: true) == .direct)
        #expect(route(e(.proYearly, lifetime: true), key: true, prefer: false) == .proxy)
        #expect(route(e(.proYearly, lifetime: true), key: false, prefer: true) == .proxy)
        #expect(route(e(.proYearly, lifetime: false), key: true, prefer: true) == .proxy)   // no licence, no switch
    }

    @Test func untilPurchasesExistAKeyIsFreeAndNeverSpendsFreeCredits() {
        #expect(route(e(.free), key: true, license: false) == .direct)
        #expect(route(e(.none), key: true, license: false) == .direct)
        #expect(route(nil, signedIn: false, key: true, license: false) == .direct)
        #expect(route(e(.proMonthly), key: true, prefer: true, license: false) == .direct)
        #expect(route(e(.proMonthly), key: true, prefer: false, license: false) == .proxy)
        #expect(route(e(.free), key: false, license: false) == .proxy)
        #expect(route(nil, signedIn: false, key: false, license: false) == .signIn)
    }
}

@Suite("BackendClient")
struct BackendClientTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func decodesMeWithAndWithoutFractionalSeconds() async throws {
        let t = FakeHTTP()
        t.body = Data(#"{"plan":"pro_yearly","runs_used":3,"runs_allowance":1000,"period_end":"2026-11-30T10:00:00Z","owns_lifetime":true,"updates_until":null,"next_upgrade_tier":2}"#.utf8)
        let me = try await BackendClient(baseURL: base, transport: t).me(accessToken: "tok")
        #expect(me.plan == .proYearly && me.plan.isPro && me.runsLeft == 997 && me.ownsLifetime)
        #expect(me.periodEnd != nil && me.updatesUntil == nil && me.nextUpgradeTier == 2)
        #expect(t.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(t.requests[0].httpMethod == "GET")
    }

    @Test func freeMeterMaths() {
        let me = EntitlementInfo(plan: .free, runsUsed: 17, runsAllowance: 21, periodEnd: now.addingTimeInterval(20.2 * 86_400))
        #expect(me.runsLeft == 4 && me.usedFraction == 17.0 / 21.0 && me.daysUntilRenewal(now: now) == 21)
        #expect(EntitlementInfo(plan: .lifetime).usedFraction == nil)
        #expect(EntitlementInfo(plan: .free, runsUsed: 0, runsAllowance: 21, periodEnd: now.addingTimeInterval(-5)).daysUntilRenewal(now: now) == 0)
    }

    @Test func verifyEmailCodeBuildsASession() async throws {
        let t = FakeHTTP()
        t.body = Data(#"{"user_id":"u1","access_token":"a","refresh_token":"r","expires_in":3600}"#.utf8)
        let s = try await BackendClient(baseURL: base, transport: t).verifyEmailCode(email: "a@b.co", code: "123456", now: now)
        #expect(s == AuthSession(userID: "u1", accessToken: "a", refreshToken: "r", accessExpiresAt: now.addingTimeInterval(3600)))
        #expect(!s.needsRefresh(now: now) && s.needsRefresh(now: now.addingTimeInterval(3560)))
        #expect(t.requests[0].url?.path == "/v1/auth/email/verify")
    }

    @Test func sendEventsPostsAnonymouslyWithNamesAndProps() async throws {
        let t = FakeHTTP()
        t.body = Data(#"{"ok":true,"accepted":2}"#.utf8)
        let events = [FunnelEvent(name: "onboarding_started", at: now),
                      FunnelEvent(name: "onboarding_step_viewed", at: now, props: ["step": "welcome"])]
        try await BackendClient(baseURL: base, transport: t).sendEvents(installIDHash: installIDHash("abc"), appVersion: "1.2.0", events: events)
        #expect(t.requests[0].url?.path == "/v1/events")
        #expect(t.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        let raw = try #require(t.requests[0].httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect(body["app_version"] as? String == "1.2.0")
        let list = try #require(body["events"] as? [[String: Any]])
        #expect(list.count == 2 && list[0]["name"] as? String == "onboarding_started" && list[0]["props"] == nil)
        #expect(list[0]["at"] as? Int == 1_800_000_000_000)
        #expect((list[1]["props"] as? [String: String]) == ["step": "welcome"])
    }

    @Test func claimingFreeCreditsSendsTheHashedInstallID() async throws {
        let t = FakeHTTP()
        t.body = Data(#"{"plan":"free","period_end":"2026-11-12T00:00:00.000Z","runs_allowance":21}"#.utf8)
        let info = try await BackendClient(baseURL: base, transport: t).claimFreeCredits(accessToken: "tok", installIDHash: installIDHash("abc"))
        #expect(info.runsAllowance == 21 && info.plan == .free && info.periodEnd != nil)
        let raw = try #require(t.requests[0].httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: raw) as? [String: String])
        #expect(body["install_id_hash"] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")   // SHA-256("abc")
    }

    @Test func surfacesServerErrorsAndRetryAfter() async {
        let t = FakeHTTP()
        t.status = 409
        t.body = Data(#"{"error":{"code":"install_already_used","message":"Free credits have already been claimed on this Mac."}}"#.utf8)
        do {
            _ = try await BackendClient(baseURL: base, transport: t).claimFreeCredits(accessToken: "t", installIDHash: "x")
            Issue.record("expected an error")
        } catch let e as BackendError { #expect(e.kind == .installAlreadyUsed && e.status == 409) } catch {}

        t.status = 429
        t.body = Data("<html>".utf8)
        t.headers = ["Retry-After": "7"]
        do {
            try await BackendClient(baseURL: base, transport: t).requestEmailCode(email: "a@b.co")
            Issue.record("expected an error")
        } catch let e as BackendError { #expect(e.retryAfter == 7 && e.code == "http_429") } catch {}
    }

    @Test func networkFailureIsUnreachable() async {
        let t = FakeHTTP()
        t.error = URLError(.notConnectedToInternet)
        do {
            _ = try await BackendClient(baseURL: base, transport: t).me(accessToken: "t")
            Issue.record("expected an error")
        } catch let e as BackendError { #expect(e.kind == .unreachable) } catch {}
    }
}

@Suite("Purchases")
struct PurchaseTests {
    @Test func productIDsMatchAppStoreConnect() {
        #expect(PaywallProduct.proYearly.storeKitID == "pro_yearly")
        #expect(PaywallProduct.proMonthly.storeKitID == "pro_monthly")
        #expect(PaywallProduct.lifetime.storeKitID == "lifetime_byok")
        #expect(PaywallProduct.lifetimeUpgrade1.storeKitID == "lifetime_upgrade_1")
        #expect(PaywallProduct.lifetimeUpgrade3.storeKitID == "lifetime_upgrade_3")
        for p in PaywallProduct.allCases { #expect(PaywallProduct(storeKitID: p.storeKitID) == p) }
        #expect(PaywallProduct(storeKitID: "gems") == nil)
        #expect(PaywallProduct.proYearly.isSubscription && !PaywallProduct.lifetime.isSubscription)
    }

    @Test func upgradeLadderFollowsTheServersTierAndStopsAtTheLast() {
        #expect([0, 1, 2, 3, 4, 9].map { PaywallProduct.upgrade(tier: $0) } ==
                [.lifetimeUpgrade1, .lifetimeUpgrade1, .lifetimeUpgrade2, .lifetimeUpgrade3, .lifetimeUpgrade3, .lifetimeUpgrade3])
        #expect(PaywallProduct.allCases.filter(\.isUpgrade).count == PaywallProduct.upgradeTiers)
    }

    @Test func receiptCallAndErrors() async throws {
        let t = FakeHTTP()
        t.body = Data(#"{"plan":"lifetime","trial_ends_at":null,"runs_used":null,"runs_allowance":null,"period_end":null,"owns_lifetime":true,"updates_until":"2027-10-22T00:00:00.000Z"}"#.utf8)
        let client = BackendClient(baseURL: base, transport: t)
        let me = try await client.submitStoreKitTransaction(accessToken: "tok", signedTransaction: "a.b.c")
        #expect(me.plan == .lifetime && me.ownsLifetime && me.updatesUntil != nil)
        #expect(t.requests[0].url?.path == "/v1/purchases/storekit")

        for (status, code, kind) in [(400, "invalid_receipt", BackendError.Kind.invalidReceipt), (409, "wrong_account", .wrongAccount)] {
            t.status = status
            t.body = Data(#"{"error":{"code":"\#(code)","message":"m"}}"#.utf8)
            do { _ = try await client.submitStoreKitTransaction(accessToken: "t", signedTransaction: "x"); Issue.record("expected error") }
            catch let e as BackendError { #expect(e.kind == kind) }
        }
    }
}

@Suite("Offline and update-window rules")
struct PolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ n: Double) -> Date { now.addingTimeInterval(n * 86_400) }

    @Test func aLifetimeLicenceIsTrustedOfflineFor14Days() {
        #expect(OfflinePolicy.lifetimeIsFresh(fetchedAt: days(-13.9), now: now))
        #expect(OfflinePolicy.lifetimeIsFresh(fetchedAt: days(-14), now: now))
        #expect(!OfflinePolicy.lifetimeIsFresh(fetchedAt: days(-14.1), now: now))
        #expect(!OfflinePolicy.lifetimeIsFresh(fetchedAt: nil, now: now))
        #expect(OfflinePolicy.graceDays == 14)
    }

    @Test func aStaleLifetimeMustBeVerifiedOnlineOnlyOnceLicencesAreEnforced() {
        let lifetime = EntitlementInfo(plan: .lifetime, ownsLifetime: true)
        func route(license: Bool, stale: Bool) -> AIRoute {
            AIClientFactory.route(signedIn: true, entitlement: lifetime, hasOwnKey: true, preferOwnKey: false, ownKeyNeedsLicense: license, entitlementIsStale: stale)
        }
        #expect(route(license: true, stale: false) == .direct)
        #expect(route(license: true, stale: true) == .verifyOnline)
        #expect(route(license: false, stale: true) == .direct)
        // Staleness never affects plans that already need the server.
        #expect(AIClientFactory.route(signedIn: true, entitlement: EntitlementInfo(plan: .proYearly), hasOwnKey: false, preferOwnKey: false, ownKeyNeedsLicense: true, entitlementIsStale: true) == .proxy)
    }

    @Test func updateWindowOnlyBlocksLifetimeOnlyUsersOnNewerBuilds() {
        let until = days(10)
        func status(_ plan: PlanKind = .lifetime, until: Date? = days(10), build: Date, patch: Bool = false, at: Date? = nil) -> UpdateWindow.Status {
            UpdateWindow.status(plan: plan, updatesUntil: until, buildDate: build, isPatchBuild: patch, now: at ?? now)
        }
        #expect(status(build: days(-30)) == .ok)
        #expect(status(build: days(10)) == .ok)                                         // released the day updates end
        #expect(status(build: days(11)) == .renewalNeeded(updatesUntil: until))
        #expect(status(.proYearly, build: days(11)) == .ok)                             // Pro is unaffected
        #expect(status(.free, build: days(11)) == .ok)
        #expect(status(until: nil, build: days(11)) == .ok)                             // unknown end: never lock anyone out
    }

    @Test func compatibilityPatchesStayAllowedForAnotherYear() {
        let until = days(10)
        #expect(UpdateWindow.status(plan: .lifetime, updatesUntil: until, buildDate: days(100), isPatchBuild: true, now: days(100)) == .ok)
        #expect(UpdateWindow.status(plan: .lifetime, updatesUntil: until, buildDate: days(100), isPatchBuild: true, now: days(10 + 366)) == .renewalNeeded(updatesUntil: until))
        #expect(UpdateWindow.status(plan: .lifetime, updatesUntil: until, buildDate: days(100), isPatchBuild: false, now: days(100)) == .renewalNeeded(updatesUntil: until))
    }

    @Test func updatesExpiredIsATypedError() {
        #expect(BackendError(code: "updates_expired", message: "").kind == .updatesExpired)
    }
}
