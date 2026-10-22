# Per My Last backend (Cloudflare Workers + D1)

Phases 2 to 4 of `docs/PRD AI Plans, Trial & BYOK.md`, built on Cloudflare Workers and D1 (SQLite) instead of the PRD's
Supabase default. It has the schema, atomic run metering, sign-in (Apple, Google, emailed code), session tokens, the trial,
the Claude proxy (`POST /v1/run`), rate limits, `GET /v1/me` and `GET /v1/templates`, and payments (Lemon Squeezy and the Mac App Store).

## Layout

| Path | What |
|---|---|
| `config.ts` | All config values (PRD section 11): trial days and credits (50), Pro allowance, caps, token lifetimes |
| `migrations/` | D1 schema (the PRD's six tables plus `users` and `refresh_tokens`) and the seeded templates |
| `src/plans.ts` | Plan resolution and monthly-period maths (pure functions) |
| `src/metering.ts` | `consumeRun`, `refundRun`, `commitRun`: the limit check is part of the write, one D1 batch per operation |
| `src/auth.ts`, `src/jwt.ts` | Apple/Google ID-token verification (RS256 against their published keys), accounts, session and refresh tokens |
| `src/app.ts` | Routes. Paths are exactly the PRD's (`/v1/...`) |
| `src/run.ts` | The proxy: limits, atomic reserve, Anthropic stream, refunds, usage events |
| `src/trial.ts`, `src/emailAuth.ts`, `src/limits.ts` | Trial start, emailed-code sign-in, per-user rate and stream limits |
| `src/purchases.ts`, `src/lemonsqueezy.ts`, `src/license.ts` | What a purchase does to an account; Lemon Squeezy webhook; licence-key activation |
| `src/appstore.ts`, `src/x509.ts` | App Store transactions and notifications: Apple-signed JWS checked against Apple Root CA - G3 |
| `scripts/` | `measure-cost.mjs` (cost per run) and `cost-report.sql` (from real usage) |
| `test/` | 97 tests in a local D1 simulation, including AC-11 directly and through the proxy |

## Endpoints

| Method and path | Body | Result |
|---|---|---|
| `POST /v1/auth/apple` | `{id_token, nonce?}` | `{user_id, access_token, refresh_token, expires_in}` |
| `POST /v1/auth/google` | `{id_token}` | same |
| `POST /v1/auth/email/request` | `{email}` | `{ok: true}` whether or not the address has an account; a 6-digit code is emailed (3 per address per 15 min) |
| `POST /v1/auth/email/verify` | `{email, code}` | session; the code works once, for 10 minutes, and locks after 5 wrong guesses |
| `POST /v1/trial/start` | `{install_id_hash}` (Bearer) | `{plan, trial_ends_at, runs_allowance}`; idempotent; `409 trial_already_used` for a second account on the same Mac |
| `POST /v1/run` | `{template_id, variables}` (Bearer) | SSE: `delta` events `{text}`, then `done` `{runs_remaining}`; or `error` `{code, message}` |
| `POST /v1/purchases/storekit` | `{signed_transaction}` (Bearer) | Verifies the Apple-signed transaction and grants the plan; returns the `/v1/me` body. Used after a purchase and for Restore |
| `POST /v1/license/activate` | `{license_key}` (Bearer) | Links a Lemon Squeezy licence key to the account; `404 unknown_license`, `409 license_already_used` |
| `POST /webhooks/lemonsqueezy` | Lemon Squeezy event, `X-Signature` header | Verifies the HMAC signature, then applies the event; always `200` for valid deliveries |
| `POST /webhooks/appstore` | `{signedPayload}` (App Store Server Notification V2) | Verifies the JWS chain, then applies renewals, refunds, grace periods |
| `POST /v1/auth/refresh` | `{refresh_token}` | same; the old refresh token is revoked, and reusing it revokes all of that user's sessions |
| `GET /v1/me` | (Bearer access token) | `{plan, trial_ends_at, runs_used, runs_allowance, period_end, owns_lifetime, updates_until}` |
| `GET /v1/templates?since_version=N` | (Bearer) | `{version, templates}`; `templates` is empty when the caller already has the newest version |

Errors are `{error: {code, message}}` (plus `limit` or `retry_after` where relevant): 401 `unauthenticated` / `invalid_token` / `invalid_code`,
402 `no_entitlement` / `trial_expired` / `trial_credits_exhausted` / `quota_exhausted` / `byok_required`, 409 `trial_already_used`,
413 `input_too_large`, 429 `rate_limited`, 502 `upstream_error` (the run is refunded), 503 `email_unavailable`, 400 / 404 / 405 / 500.

## Run the tests

```bash
cd backend && npm install
npm test            # 97 tests: plans, metering, AC-11 (100 parallel runs), auth, trial, proxy, payments
npm run typecheck
../scripts/check-secrets.sh   # AC-12; pass a built .app path to scan it too
```

## Developer steps (not done by Claude)

Needs a free Cloudflare account.

1. `cd backend && npx wrangler login`
2. `npx wrangler d1 create permylast`, then put the printed `database_id` into `wrangler.jsonc`.
3. `npx wrangler d1 migrations apply permylast --remote`
4. Secrets (never commit them; each command prompts for the value):
   `openssl rand -base64 48 | npx wrangler secret put JWT_SECRET`, `npx wrangler secret put ANTHROPIC_API_KEY` (the shared key;
   set a monthly spend limit on your Anthropic organisation first), and for sign-in emails `npx wrangler secret put RESEND_API_KEY`
   plus a `MAIL_FROM` var in `wrangler.jsonc` (a sender on a domain you verified with Resend).
5. Fill in `GOOGLE_CLIENT_ID` in `wrangler.jsonc` (your OAuth client id; it is public). `APPLE_CLIENT_ID` is already the app's bundle id.
   Sign in with Apple needs the Apple Developer Program ($99/yr) and the capability enabled for `app.permylast`.
6. `npx wrangler deploy`. The app's `BACKEND_URL` is the `*.workers.dev` address it prints.
7. Smoke test: sign in from the app (Phase 3) or `curl` `/v1/templates` with a token.

## Payments setup (developer steps, test mode first)

Nothing here is done by Claude: no real purchases, no store settings changed.

**Lemon Squeezy (direct build).** 1) Create a store and, in **test mode**, four products: Lifetime (one-time, with licence keys on), Lifetime renewal
(one-time), Pro Monthly and Pro Yearly (subscriptions). 2) Put each variant id into `wrangler.jsonc` (`LS_VARIANT_*`) and each product's checkout link into
`App/PerMyLast/AppConfig.swift` (`checkoutLinks`). 3) Add a webhook pointing at `https://<your-worker>/webhooks/lemonsqueezy`, subscribed to
`order_created`, `order_refunded`, `subscription_*`, `subscription_payment_refunded` and `license_key_created`, and `npx wrangler secret put LS_WEBHOOK_SECRET` with its signing secret.
4) While testing set `LS_ACCEPT_TEST_MODE` to `"true"`. Field names in `src/lemonsqueezy.ts` follow Lemon Squeezy's docs but were not checked against live deliveries:
make one test purchase of each product and watch the Worker log (`npx wrangler tail`) before trusting them.

**Mac App Store build.** 1) In App Store Connect create `lifetime_byok` (non-consumable), `lifetime_renewal` (consumable), and `pro_monthly` / `pro_yearly`
(auto-renewing, one subscription group). 2) Add the In-App Purchase capability to the app (needs the Apple Developer Program and real signing). 3) Set the App Store Server Notifications V2
URL (sandbox and production) to `https://<your-worker>/webhooks/appstore`. 4) While testing set `APPSTORE_ENVIRONMENTS` to `"Production,Sandbox"`. The app sets `appAccountToken` to the user id on every purchase;
the Worker checks the Apple signature chain against the pinned root, the bundle id, the environment and the account before granting anything.
Purchases made with Xcode's local StoreKit configuration are signed by a local test certificate, not Apple's, so the Worker rejects them: test with a sandbox account instead.

**Before launch:** remove `APPSTORE_ENVIRONMENTS` sandbox and set `LS_ACCEPT_TEST_MODE` back to `"false"`, then set `AppConfig.paymentsLive = true` (this is what makes an own key require Lifetime).

## Behaviour notes

- **Purchases.** Buying anything ends the trial at once and drops unused credits. A Lifetime entitlement never expires and carries `updates_until` (12 months from purchase);
  a renewal adds 12 months from today or from the current end, once per order. Pro: `expires_at` is the paid-through date; cancelling keeps access to it; a payment retry keeps
  access for `GRACE_DAYS`; a refund revokes. A provider's older event cannot undo a newer one (`source_updated_at`).
- **Webhooks are idempotent.** Deliveries are recorded after they are applied, by body hash (Lemon Squeezy) or notification id (App Store).
- **Test payments cannot unlock production.** Lemon Squeezy test-mode events and App Store sandbox transactions are ignored unless the deployment opts in.
- **Licence keys.** A purchase made while signed out waits as a pending licence until its key is entered in the app; only a hash of each key is stored.

- **No row-level security.** Clients never reach D1; the Worker does, and scopes every query to the user id in a verified token.
- **Metering.** Resolution order: active Pro, then Lifetime, then active trial with credits left, else none.
  `consumeRun` errors: `byok_required`, `quota_exhausted`, `trial_credits_exhausted`, `trial_expired`, `no_entitlement`;
  `/v1/run` (Phase 3) maps them to the PRD's HTTP codes. `commitRun` is an addition: it stops a late refund taking back a delivered run.
- **Pro periods** count monthly from the entitlement's `starts_at`, yearly plans too. Webhooks (Phase 4) must upsert by
  `(source, external_id)`, keep `starts_at` stable across renewals, and set `expires_at` to the paid-through date.
- **Accounts.** The same verified email on Apple and Google is one account. An unverified email never links accounts.
- **Emailed code instead of a link.** A 6-digit code works in a sandboxed menu bar app without a URL scheme. Email goes through Resend
  (a default; swap `src/email.ts` for another provider). `MAIL_MODE=log` prints codes to the Worker log for local development only; never set it in production.
- **The proxy takes the prompt text as a variable.** `/v1/run` accepts `{template_id, variables}`; the system prompt, model, `max_tokens` and
  key stay on the server, and input is capped at `MAX_INPUT_CHARS`. The app sends its fully built prompt (including the user's edited presets) as
  the `content` variable, so a signed-in user can send arbitrary text as the user message. The caps bound the cost; tighten them in `config.ts`.
- **Refunds.** Any failure before the first streamed text (upstream error, timeout, client disconnect) refunds the run; once text is delivered the run is committed.
- **Placeholders to set from measured cost:** `MAX_OUTPUT_TOKENS` (1,024 also caps the Ask tab, whose template asks for 4,096), `DEFAULT_MODEL`, `MAX_INPUT_CHARS`, prices.
  Measure with `ANTHROPIC_API_KEY=... INPUT_USD_PER_MTOK=... OUTPUT_USD_PER_MTOK=... node scripts/measure-cost.mjs`.
- **Not built yet:** payments and webhooks (Phase 4), cost-weighting for larger models and the CI secret scan (Phase 5).
- **Free-tier limits** change over time; check Cloudflare's current Workers and D1 limits before launch.
- `npm audit` reports high-severity findings in the dev tooling (wrangler, vitest). The deployed Worker has no runtime dependencies.
