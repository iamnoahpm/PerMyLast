# PRD: AI Plans, Trial & BYOK

Oct 22, 2026 · @Noah

## 1. Overview

Add three ways to use the app's AI features to the existing macOS app: a 21-day free trial with credits, a one-time Lifetime license where users bring their own Claude API key (BYOK), and a Pro subscription that uses the developer's shared key with a monthly run allowance.

**Goals**

- Let new users try the default prompts with zero setup for 21 days.
- Offer a low-cost path (Lifetime + own key) and a zero-setup path (Pro + hosted credits).
- Never expose the shared Anthropic API key; keep the cost per user predictable.

**In scope:** prompt templates, Claude API integration (Anthropic only for now), sign-in, trial, quota metering, backend proxy, payments, paywall, BYOK key setup, usage meter.

**Out of scope (v1):** other AI providers, teams/seats, top-up packs, admin dashboard UI (SQL queries are enough for v1).

**How Claude Code should use this PRD**

1. Read the existing codebase first and summarise its structure, UI framework, networking and persistence before changing anything.
2. Integrate with existing patterns; do not rewrite unrelated code.
3. Build one phase at a time (section 10). Stop after each phase, run the build and tests, and report.
4. Requirement IDs (FR-A1, FR-B3 …) are referenced in acceptance criteria; mention them in commit messages.
5. Values in \[brackets\] are config, not hard-coded. Ask about anything in section 11 that blocks the current phase.

## 2. Plans and entitlements

Every signed-in user has exactly one effective plan, resolved on the server; the app decides which AI client to use from it.

| Plan | How obtained | AI route | Limit | Ends when |
| --- | --- | --- | --- | --- |
| `none` | Default before trial / after expiry | Blocked (history and export still work) | 0 runs | — |
| `trial` | First sign-in, once per user and device | Proxy, shared key | \[TRIAL\_CREDITS\] runs total | 21 days after start OR credits used up, whichever first |
| `lifetime` | One-time purchase | Direct to Anthropic with user's own key | None from us (user pays Anthropic) | Never; updates until `updates_until` |
| `pro_monthly` | Monthly subscription | Proxy, shared key | \[PRO\_MONTHLY\_RUNS\] runs per month | Subscription lapses |
| `pro_yearly` | Yearly subscription | Proxy, shared key | \[PRO\_MONTHLY\_RUNS\] runs per month, reset monthly | Subscription lapses |

**Resolution order** (first match wins): active Pro → Lifetime → active trial → none.

- A user with both Lifetime and active Pro uses the proxy by default, with a setting "Use my own API key instead".
- Users can buy Lifetime or Pro at any time during the trial; the trial ends immediately and unused trial credits are dropped.
- When Pro lapses and the user also owns Lifetime, they fall back to Lifetime (BYOK) without losing anything.

**What counts as a run:** one successful prompt execution through the proxy. Failed, cancelled-before-first-token or timed-out requests are refunded automatically.

## 3. Architecture

The app talks to Anthropic directly only in BYOK mode; every request using the shared key goes through a backend proxy that owns auth, plan checks and metering.

```text
 Mac app (SwiftUI)
  ├─ AIClient (protocol)
  │   ├─ DirectAnthropicClient ── user key (Keychain) ──► api.anthropic.com
  │   └─ ProxyClient ── user JWT ──► Backend /v1/run ── shared key ──► api.anthropic.com
  ├─ EntitlementStore  ◄── GET /v1/me
  ├─ TemplateStore     ◄── GET /v1/templates (bundled fallback)
  └─ PurchaseService   ──► StoreKit 2  or  Paddle / Lemon Squeezy checkout

 Backend (default: Supabase — Auth + Postgres + Edge Functions)
  ├─ Auth: Sign in with Apple, Google, email magic link
  ├─ Edge functions: run, me, templates, trial-start, license-activate, webhooks
  └─ Postgres: users, entitlements, usage_periods, usage_events, templates

 Payment provider ── webhooks / App Store Server Notifications ──► entitlements table
```

**Defaults** (change in section 11 if the existing app already uses something else): Supabase for the backend, Anthropic Messages API with streaming, StoreKit 2 + RevenueCat if distributed on the Mac App Store, Paddle if sold directly.

The server is the source of truth for every plan. The app caches the last `/v1/me` response for display and offline Lifetime use only.

## 4. App requirements (FR-A)

The app gains one AI abstraction, an entitlement store, BYOK key setup, a usage meter and a paywall.

**AI clients**

- **FR-A1** Define `protocol AIClient { func run(templateID: String, variables: [String: String]) -> AsyncThrowingStream<String, Error> }`. All AI features call this protocol only.
- **FR-A2** `DirectAnthropicClient` calls `POST https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`, `stream: true`. It renders the template locally and streams text deltas.
- **FR-A3** `ProxyClient` calls `POST {BACKEND_URL}/v1/run` with `Authorization: Bearer <user JWT>` and streams the server-sent events back. It maps server error codes (section 5) to typed errors.
- **FR-A4** `AIClientFactory` picks the client from the effective plan: Pro or trial → Proxy; Lifetime with a saved key → Direct; Lifetime without a key → open key setup; none → paywall.

**Prompt templates**

- **FR-A5** Templates are JSON: `id`, `title`, `description`, `system`, `user_template` (with `{{variable}}` placeholders), `variables`, `model`, `max_tokens`, `version`.
- **FR-A6** Fetch `GET /v1/templates` at launch and every 24 h; cache to disk; ship a bundled copy as fallback. BYOK users use the same templates.

**Sign-in and trial**

- **FR-A7** Sign in with Apple, Google and email magic link via the backend's auth SDK. Store the session securely; refresh tokens silently.
- **FR-A8** Generate a random install ID on first launch and store it in the Keychain (survives reinstall). Send its SHA-256 hash with `POST /v1/trial/start`.
- **FR-A9** After first sign-in, start the trial automatically and show "Trial: \[N\] runs · 21 days left".

**BYOK key setup**

- **FR-A10** Key setup screen: provider = Anthropic, secure text field, "Test key" button, link to the Anthropic Console's API key page, note that the user pays Anthropic directly.
- **FR-A11** "Test key" sends a minimal request (`max_tokens: 1`) and shows success or the API's error message (invalid key, no credit, rate limit).
- **FR-A12** Store the key in the Keychain only (`kSecAttrAccessibleAfterFirstUnlock`), never in UserDefaults, logs, analytics or the backend. Allow replace and delete.

**Usage, paywall and states**

- **FR-A13** Usage meter in the main UI and Settings: trial (runs left, days left), Pro (used / allowance, reset date), Lifetime ("Using your Anthropic key").
- **FR-A14** Warn once at 80% of the trial or monthly allowance and once 3 days before the trial ends.
- **FR-A15** Show the paywall when the server returns `trial_expired`, `trial_credits_exhausted` or `no_entitlement`, and from a "Upgrade" menu item. Yearly pre-selected; Monthly second; Lifetime BYOK as a secondary link.
- **FR-A16** On `quota_exhausted` (Pro), show the reset date and the option to switch to own key if the user owns Lifetime.
- **FR-A17** When blocked, history, viewing and export keep working; only new runs are disabled.
- **FR-A18** "Restore purchases" in the paywall and Settings.

## 5. Backend requirements (FR-B) and API contract

The backend authenticates users, resolves plans, meters runs atomically and proxies Claude calls with the shared key.

**Run proxy (`POST /v1/run`)**

- **FR-B1** Verify the JWT. Resolve the effective plan (section 2). Lifetime-only users get `402 byok_required`.
- **FR-B2** Check limits: trial within 21 days and credits left; Pro `used < allowance` for the current period (create the period row if missing).
- **FR-B3** Reserve one run atomically with a Postgres function `consume_run(user_id) returns reservation_id`, using `UPDATE … SET used = used + 1 WHERE used < allowance RETURNING`. No read-then-write.
- **FR-B4** Load the template by ID server-side; render variables; reject unknown templates. The client never sends a raw system prompt or model name.
- **FR-B5** Enforce limits: input ≤ \[MAX\_INPUT\_CHARS\], `max_tokens` = min(template value, \[MAX\_OUTPUT\_TOKENS\]), model from template or \[DEFAULT\_MODEL\].
- **FR-B6** Call the Anthropic Messages API with the shared key from a server secret, `stream: true`, and `cache_control: {type: "ephemeral"}` on the system block to use prompt caching. Stream text deltas to the client as SSE.
- **FR-B7** On upstream error, timeout (\[UPSTREAM\_TIMEOUT\_S\]) or client disconnect before the first token: call `refund_run(reservation_id)`.
- **FR-B8** Write a `usage_events` row with model, input/output/cache tokens, latency, status.
- **FR-B9** Rate limit per user: \[RATE\_LIMIT\_PER\_MIN\] requests/minute and 2 concurrent streams.

**Other endpoints**

| Method & path | Request | Response |
| --- | --- | --- |
| `POST /v1/run` | `{template_id, variables}` | SSE: `delta` events with text, then `done` with `{runs_remaining}` |
| `GET /v1/me` | — | `{plan, trial_ends_at, runs_used, runs_allowance, period_end, owns_lifetime, updates_until}` |
| `GET /v1/templates` | `?since_version=` | `{version, templates: [...]}` |
| `POST /v1/trial/start` | `{install_id_hash}` | `{plan, trial_ends_at, runs_allowance}`; idempotent |
| `POST /v1/license/activate` | `{license_key}` (direct sale only) | `{owns_lifetime, updates_until}` |
| `POST /webhooks/paddle` | Provider payload, signature verified | 200 |
| `POST /webhooks/appstore` | App Store Server Notification v2 (or RevenueCat webhook) | 200 |

**Error codes** (JSON body `{error: {code, message}}`)

| HTTP | code | App behaviour |
| --- | --- | --- |
| 401 | `unauthenticated` | Refresh session, else sign-in |
| 402 | `no_entitlement` / `trial_expired` / `trial_credits_exhausted` | Paywall |
| 402 | `quota_exhausted` | Show reset date (FR-A16) |
| 402 | `byok_required` | Key setup |
| 409 | `trial_already_used` | Paywall with message |
| 413 | `input_too_large` | Inline error with the limit |
| 429 | `rate_limited` | Retry after `retry_after` seconds |
| 502 | `upstream_error` | "Try again" (run already refunded) |

## 6. Data model

Six Postgres tables plus two functions; enable row-level security so users can read only their own rows and only the service role writes.

| Table | Columns | Notes |
| --- | --- | --- |
| `profiles` | `user_id` PK (auth user), `install_id_hash`, `created_at` | One trial per `user_id` and per `install_id_hash` |
| `entitlements` | `id`, `user_id`, `plan` (trial, lifetime, pro\_monthly, pro\_yearly), `status` (active, expired, refunded), `starts_at`, `expires_at`, `updates_until`, `source` (storekit, paddle, manual), `external_id`, `updated_at` | Webhooks upsert by `external_id`; history kept |
| `usage_periods` | `id`, `user_id`, `kind` (trial, pro), `period_start`, `period_end`, `allowance`, `used` | Unique (`user_id`, `kind`, `period_start`); `CHECK (used <= allowance)` |
| `run_reservations` | `id`, `usage_period_id`, `status` (reserved, committed, refunded), `created_at` | Lets refunds be idempotent |
| `usage_events` | `id`, `user_id`, `template_id`, `model`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `latency_ms`, `status`, `created_at` | Cost reporting; no prompt or output text stored |
| `templates` | `id`, `version`, `json`, `active` | Served by `/v1/templates` |

**Functions**

- `consume_run(user_id uuid) returns uuid` — locks the current period row, increments `used` if below `allowance`, inserts a reservation; raises `quota_exhausted` otherwise.
- `refund_run(reservation_id uuid)` — if status is `reserved`, decrements `used` and marks `refunded`; otherwise no-op.

Pro periods: monthly from the subscription's anchor date (yearly plans too). Unused runs do not carry over in v1.

## 7. Payments and licensing

Implement the distribution channel the existing app already uses (section 11, decision D1); both paths write to the same `entitlements` table.

**Products**

| Product ID | Type | Grants |
| --- | --- | --- |
| `lifetime_byok` | One-time (non-consumable / license key) | `lifetime`, `updates_until` = purchase date + 12 months |
| `lifetime_renewal` | One-time, repeatable | Extends `updates_until` to max(now, current) + 12 months |
| `pro_monthly` | Auto-renewing subscription | `pro_monthly` while active |
| `pro_yearly` | Auto-renewing subscription | `pro_yearly` while active |

**Path A: Mac App Store**

- **FR-P1** StoreKit 2 for purchase and restore; RevenueCat recommended to receive server notifications and map them to `entitlements`.
- **FR-P2** Link purchases to the signed-in user via `appAccountToken` = the user's UUID.

**Path B: Direct sale (Paddle default)**

- **FR-P3** Checkout opens in the browser with the user ID as custom data; the webhook verifies the signature and upserts the entitlement.
- **FR-P4** Lifetime also issues a license key; `POST /v1/license/activate` links it to the account for users who bought before signing in.

**Common**

- **FR-P5** Handle renewal, cancellation (keep access to period end), refund (revoke), billing retry/grace period.
- **FR-P6** Webhooks are idempotent (dedupe by event ID) and logged.
- **FR-P7** Lifetime update window: each app build embeds its release date; if a Lifetime-only user's `updates_until` is earlier than the build date, show "Renew updates to use this version" with a link to download their last eligible version. Compatibility fixes released as patch builds are allowed for 24 months after purchase.

## 8. Security, cost controls and non-functional requirements

The shared key never leaves the server, and every shared-key run is capped in tokens, rate and count.

**Security**

- **NFR-1** The shared Anthropic key exists only as a backend secret. The app binary, logs and repo contain no key. Add a CI check that fails on strings matching `sk-ant-`.
- **NFR-2** BYOK keys stay in the user's Keychain and are sent only to `api.anthropic.com`.
- **NFR-3** All backend tables use row-level security; webhooks verify signatures; service-role keys are server-only.
- **NFR-4** Do not store prompt inputs or outputs on the server. Logs hold token counts and status only.

**Cost controls**

- **NFR-5** Per-run caps: \[MAX\_INPUT\_CHARS\] input, \[MAX\_OUTPUT\_TOKENS\] output; templates cannot exceed them.
- **NFR-6** Default model \[DEFAULT\_MODEL\]; a template using a more expensive model costs \[EXPENSIVE\_MODEL\_WEIGHT\] runs.
- **NFR-7** Prompt caching on template system prompts (FR-B6).
- **NFR-8** Set a monthly spend limit on the Anthropic organisation and an alert at 80%.
- **NFR-9** Daily SQL report: cost per plan, top 20 users by tokens, trial-to-paid conversion.

**Quality**

- **NFR-10** The proxy adds less than 150 ms (p50) before the first streamed token, compared with calling Anthropic directly.
- **NFR-11** Offline: Lifetime BYOK works with a cached entitlement for \[OFFLINE\_GRACE\_DAYS\] days; proxy plans show "You're offline".
- **NFR-12** Unit tests for entitlement resolution, client factory, template rendering, error mapping; integration tests for `consume_run`/`refund_run` concurrency (100 parallel calls never exceed allowance).

## 9. Acceptance criteria

Each phase is done when its criteria pass on a clean install and a test account.

| # | Given | When | Then | Covers |
| --- | --- | --- | --- | --- |
| AC-1 | New user, never signed in | Signs in | Trial starts: \[TRIAL\_CREDITS\] runs, ends in 21 days; meter visible | FR-A7–A9, FR-B2 |
| AC-2 | Trial user | Runs a template | Response streams; runs remaining decreases by 1 | FR-A3, FR-B1–B8 |
| AC-3 | Trial user | Upstream returns an error | Error shown; runs remaining unchanged | FR-B7 |
| AC-4 | Trial at day 22 or 0 runs left | Runs a template | 402; paywall opens; history still readable | FR-A15, FR-A17 |
| AC-5 | User reinstalls app or makes a new account on the same Mac | Signs in | No second trial (`trial_already_used`) | FR-A8 |
| AC-6 | Trial user | Buys Lifetime, saves a valid key | Requests go to api.anthropic.com directly; backend `usage_events` gets no row | FR-A2, FR-A4, FR-A10–A12 |
| AC-7 | Lifetime user | Enters an invalid key and taps Test | Clear error; key not saved as valid | FR-A11 |
| AC-8 | Trial user | Subscribes Pro Yearly | Plan = pro\_yearly; allowance \[PRO\_MONTHLY\_RUNS\]; resets monthly | FR-P1–P5 |
| AC-9 | Pro user at allowance | Runs a template | `quota_exhausted` with reset date | FR-A16 |
| AC-10 | Pro user | Cancels | Access until period end, then plan resolves to lifetime or none | FR-P5 |
| AC-11 | Any | 100 concurrent runs at allowance − 1 | Exactly 1 succeeds | FR-B3, NFR-12 |
| AC-12 | Any | Search app bundle and repo for `sk-ant-` | No match | NFR-1 |
| AC-13 | Purchase on device A | Restore on device B, same account | Same plan on B | FR-A18 |

## 10. Implementation phases for Claude Code

Build in six phases; each ends with a passing build, tests, and a short report before starting the next.

1. **Phase 0 — Discovery (no code changes).** Map the existing app: targets, min macOS, UI framework, networking, persistence, current AI or paywall code, distribution channel. Propose where the new modules live and list conflicts with this PRD.
2. **Phase 1 — AI abstraction + BYOK.** FR-A1, A2, A5, A6 (bundled templates only), A10–A12. Route existing AI features through `AIClient`. Exit: AC-6 (minus purchase), AC-7.
3. **Phase 2 — Backend foundation.** Supabase project via migrations in the repo (`/backend`), auth, tables, RLS, `consume_run`/`refund_run`, `/v1/me`, `/v1/templates`. Exit: AC-11, AC-12.
4. **Phase 3 — Proxy + trial.** FR-B1–B9, `/v1/trial/start`, `ProxyClient`, FR-A3, A4, A7–A9, A13, A14. Exit: AC-1 to AC-5.
5. **Phase 4 — Payments.** Section 7 for the chosen channel, FR-A15–A18, paywall UI. Use sandbox / test mode only. Exit: AC-6, AC-8 to AC-10, AC-13.
6. **Phase 5 — Hardening.** NFR-5 to NFR-12, cost report SQL, CI secret scan, lifetime update-window check (FR-P7). Exit: all ACs pass.

**Working rules for Claude Code**

- Never put real API keys, payment secrets or service-role keys in code; use `.env` (git-ignored) and Xcode build settings / a `Secrets.xcconfig` excluded from git.
- Keep config values from section 11 in one place on each side (`AppConfig.swift`, `backend/config.ts`).
- Add or update tests with every requirement implemented.
- Do not run real purchases, deploy to production, or change App Store Connect / Paddle settings; list those steps for the developer instead.

## 11. Open decisions and config values

Fill these before Phase 3; defaults are suggestions, not commitments.

**Decisions**

| # | Decision | Options | Suggested default |
| --- | --- | --- | --- |
| D1 | Distribution channel | Mac App Store / direct (Paddle, Lemon Squeezy) / both | Whatever the app uses today |
| D2 | Backend | Supabase / Cloudflare Workers + D1 / existing backend | Supabase |
| D3 | Allow anonymous runs before sign-in? | Yes (N runs) / No | No for v1 |
| D4 | BYOK providers | Anthropic only / + OpenAI, Google later | Anthropic only |
| D5 | Pro + Lifetime owner default route | Proxy / own key | Proxy |

**Config values**

| Key | Meaning | Suggested |
| --- | --- | --- |
| `TRIAL_DAYS` | Trial length | 21 |
| `TRIAL_CREDITS` | Runs in the trial | \[e.g. 50–100, set from cost per run\] |
| `PRO_MONTHLY_RUNS` | Pro allowance per month | 1000 |
| `DEFAULT_MODEL` | Model for templates without one | A Haiku-class Claude model; check current model IDs at docs.claude.com |
| `MAX_INPUT_CHARS` | Input cap per run | \[e.g. 12,000\] |
| `MAX_OUTPUT_TOKENS` | Output cap per run | \[e.g. 1,024\] |
| `EXPENSIVE_MODEL_WEIGHT` | Runs charged for a larger model | \[e.g. 4\] |
| `RATE_LIMIT_PER_MIN` | Requests per user per minute | 20 |
| `UPSTREAM_TIMEOUT_S` | Anthropic call timeout | 60 |
| `OFFLINE_GRACE_DAYS` | Lifetime offline validity | 14 |
| Prices | Pro Monthly, Pro Yearly, Lifetime, renewal | \[Set after measuring average cost per run in Phase 3\] |

**Pricing check before launch:** average cost per run × `PRO_MONTHLY_RUNS` × expected utilisation must stay well below the monthly price after store fees.
