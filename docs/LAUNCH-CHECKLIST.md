# Launch checklist (go-live)

Tick each item before the live deploy. Details live in `backend/README.md`, `docs/ACCEPTANCE.md` and `docs/RELEASE.md`.

## 1. Backend settings (`backend/wrangler.jsonc`)

- [ ] `APPSTORE_ENVIRONMENTS` is `"Production"` (not `"Production,Sandbox"`). Check: `grep APPSTORE_ENVIRONMENTS backend/wrangler.jsonc`
- [ ] `APPLE_TEAM_ID` and `APPLE_KEY_ID` are filled in, and the secret is set: `npx wrangler secret put APPLE_PRIVATE_KEY < AuthKey_XXXX.p8` (Apple requires token revocation on account deletion)
- [ ] `GOOGLE_CLIENT_ID` is filled in, if Google sign-in ships
- [ ] Secrets exist: `JWT_SECRET`, `ANTHROPIC_API_KEY`, `RESEND_API_KEY`. `MAIL_MODE=log` is NOT set
- [ ] `LS_ACCEPT_TEST_MODE` is `"false"` or absent
- [ ] Redeploy after any change: `cd backend && npx wrangler deploy`

## 2. Money and limits

- [ ] Anthropic console: monthly spend limit and 80% alert (NFR-8)
- [ ] `backend/scripts/measure-cost.mjs` run; `MAX_OUTPUT_TOKENS`, `DEFAULT_MODEL`, `MODEL_RUN_WEIGHTS`, `MAX_INPUT_CHARS` and prices set
- [ ] `backend/scripts/measure-latency.mjs` run against the deployed Worker (NFR-10)

## 3. App Store Connect

- [ ] Products created: `lifetime_byok`, `lifetime_upgrade_1..3`, `pro_monthly`, `pro_yearly`
- [ ] Server Notifications V2 URL set (sandbox and production): `https://permylast-api.iamnoahpm.workers.dev/webhooks/appstore`
- [ ] One sandbox purchase of each product done, watched with `npx wrangler tail`
- [ ] Restore purchases tested on a signed build

## 4. App (`App/PerMyLast/AppConfig.swift`)

- [ ] `paymentsLiveInRelease = true`
- [ ] `releaseDate` set to today; `isPatchBuild` right
- [ ] `backendURLString` is the production Worker URL
- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` bumped
- [ ] Signed with the Apple team; Sign in with Apple capability on

## 5. Verify before shipping

- [ ] `scripts/check-secrets.sh` clean
- [ ] `cd Packages/PerMyLastCore && swift test` and `cd backend && npm test` pass
- [ ] Release build tested on a clean install with a test account (sign in, trial, run, paywall, delete account)
- [ ] DMG opens on a Mac that never ran a dev build, no Gatekeeper warning (`docs/RELEASE.md`)

## 6. Website (only when you say so)

- [ ] Previewed locally first. The website is never deployed until you explicitly say it is ready.
