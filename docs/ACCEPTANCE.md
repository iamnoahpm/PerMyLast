# Acceptance matrix and launch checklist

Status after Phase 5. Counts: backend 103 tests, Core package 153 tests, app builds, secret scan clean (repo and built app).
"Automated" means a test in this repo passes. "Local run" means exercised against a local Worker and fake upstream.
"Needs your accounts" means it cannot be proven without a deployed Worker, Apple signing or a real Anthropic key.

| AC | What | Evidence | Still to check yourself |
|---|---|---|---|
| AC-1 | New user signs in: trial starts (50 runs, 21 days), meter visible | Automated (trial start, email sign-in). Local run: sign in, trial, `/v1/me` | Meter and Account section on screen (not seen; the automation could not capture the window) |
| AC-2 | Trial run streams, runs left drops by 1 | Automated; local run with the real `ProxyClient` (streamed in pieces, 49 left) | A run with a real Anthropic key through the deployed Worker |
| AC-3 | Upstream error: error shown, runs unchanged | Automated (error status, network failure, dying stream, client disconnect, heavy-model refund) | — |
| AC-4 | Day 22 or 0 credits: 402, paywall opens, history readable | Automated (`trial_expired`, `trial_credits_exhausted`, `no_entitlement`; no call reaches Anthropic). App opens the paywall on those codes (builds) | Paywall opening on screen. The app has no history or export feature, so only new runs are blocked (FR-A17) |
| AC-5 | Reinstall or second account on the same Mac: no second trial | Automated (`trial_already_used`, same account on another install gets the same trial). Local run: second account refused | The install id is a Keychain item; confirm it survives deleting and reinstalling the app |
| AC-6 | Trial user buys Lifetime, saves a valid key: requests go straight to Anthropic, none through the backend | Automated: Lifetime ends the trial and the proxy answers `byok_required`; the direct client, key storage and routing are tested | A real test purchase (App Store sandbox), then one run with your key |
| AC-7 | Invalid key + Test: clear error, not marked valid | Automated (401, no credit, rate-limit messages). A valid key was tested live | Invalid key on screen |
| AC-8 | Trial user subscribes Pro Yearly: plan, allowance, monthly reset | Automated (signed App Store transaction and notifications). Local run | Real test subscription |
| AC-9 | Pro at allowance: `quota_exhausted` with reset date | Automated; the app shows the reset date and "Use my own API key instead" for Lifetime owners | On screen |
| AC-10 | Cancel: access to period end, then Lifetime or none | Automated (cancel, grace period, expiry, refund, fallback to Lifetime). Local run | Real cancellation in both stores |
| AC-11 | 100 concurrent runs at allowance - 1: exactly one succeeds | Automated against a simulated D1: directly, through the proxy (one call reaches Anthropic), and for 4-run heavy reservations | Repeat once on the deployed D1 |
| AC-12 | No `sk-ant-` key in the bundle or repo | `scripts/check-secrets.sh` clean on the repo and the built app; CI runs it on every push | Add the repo to GitHub so CI actually runs |
| AC-13 | Purchase on device A, restore on B, same account | Automated: the plan lives on the server, so signing in on B shows it; resending a transaction is harmless | StoreKit "Restore purchases" on a signed build (the code path has never run) |

## Phase 5 items

| Requirement | State |
|---|---|
| NFR-5 per-run caps | Done: input cap, output cap; a template cannot exceed them (tested) |
| NFR-6 larger models cost more runs | Done: `MODEL_RUN_WEIGHTS` per model id (all 1 for now) with `DEFAULT_RUN_WEIGHT` for unlisted ones; refunds give back the same weight |
| NFR-7 prompt caching | In place (`cache_control` on the system block). The built-in system prompts are short, so Anthropic may not cache them; no effect until prompts grow |
| NFR-8 Anthropic spend limit and 80% alert | **Yours to do** in the Anthropic console. Not done |
| NFR-9 daily cost report | `backend/scripts/cost-report.sql`: cost by plan, top 20 users, conversion, failures |
| NFR-10 proxy adds under 150 ms at p50 | Local run: +11 ms. Production not measured; D1 round trips there will cost more. The proxy was trimmed to four sequential D1 calls before the first token. Run `backend/scripts/measure-latency.mjs` against the deployed Worker |
| NFR-11 offline | Lifetime trusted for 14 days since the server last confirmed it (enforced once `paymentsLive`), then "Connect to the internet to verify your license". Proxy plans say "You're offline" |
| NFR-12 tests | Entitlement resolution, client routing, template rendering, error mapping, and concurrency tests are in |
| FR-P7 update window | Done: a Lifetime-only user whose updates ended before this build's release date sees "Renew updates to use this version" (Pro unaffected); patch builds get 12 more months. `AppConfig.releaseDate` must be set for every release |
| CI secret scan (NFR-1) | `.github/workflows/ci.yml`: secret scan, backend tests, Core tests. There is no git remote yet, so it has not run |

## Launch checklist

1. Anthropic console: set a monthly spend limit and an 80% alert (NFR-8).
2. Cloudflare: create the D1 database, apply migrations, set secrets and variables (`backend/README.md`), deploy, and put the Worker URL in `AppConfig.backendURLString`.
3. Run `backend/scripts/measure-cost.mjs` with your key and model prices; set `MAX_OUTPUT_TOKENS`, `DEFAULT_MODEL`, `MODEL_RUN_WEIGHTS`, `MAX_INPUT_CHARS`, then the prices.
   Note the Ask tab asks for 4096 tokens but the placeholder cap is 1024.
4. Run `backend/scripts/measure-latency.mjs` against the deployed Worker (NFR-10).
5. App Store Connect: create the products and the Server Notifications URL, then make one sandbox purchase of each product and watch `wrangler tail`.
6. Sign the app with your Apple team (needed for StoreKit and Sign in with Apple; the app signs in with Apple only).
7. Remove the test settings: `APPSTORE_ENVIRONMENTS` back to `Production`.
8. Set `AppConfig.paymentsLiveInRelease = true`. From then on a saved own key requires a Lifetime licence, so existing key users will be asked to buy it.
9. Set `AppConfig.releaseDate` for the build.
10. Push the repo to GitHub so CI runs, then walk the unchecked cells above on a clean install with a test account.

## Known gaps

- Never run: StoreKit purchase and restore, Sign in with Apple, Google sign-in, real sign-in emails (Resend), the Apple certificate check against a real Apple signature
  (tested with a generated chain; the pinned root matches the certificate downloaded from apple.com), and the new Account and paywall screens.
- `npm audit` reports findings in dev tooling only; the Worker has no runtime dependencies.
