# Phase 0 — Discovery (AI Plans, Trial & BYOK)

Read-only survey of the codebase against `PRD AI Plans, Trial & BYOK.md`. No code was changed.
Baseline: `swift test` in `Packages/PerMyLastCore` passes (107 tests, 18 suites); the Mac app builds.

## Decisions received for Phase 3

| Item | Answer |
|---|---|
| D1 Distribution | **Both**: Mac App Store (StoreKit 2) and **Lemon Squeezy** direct (replaces Paddle everywhere in the PRD, e.g. `/webhooks/lemonsqueezy`) |
| `TRIAL_CREDITS` | **50** |
| Prices | Placeholders; set after measuring cost per run in Phase 3 |
| D2 Backend | **Cloudflare Workers + D1** (changed from the PRD's Supabase default, because it is free and does not pause). Sign-in is built in the Worker: Apple and Google ID tokens are verified there; email magic link needs an email provider (open) |
| D3–D5, other config | Still PRD defaults (no anonymous runs, Anthropic only, Pro+Lifetime defaults to proxy) |

## 1. Structure

- **`Packages/PerMyLastCore`** (SwiftPM, tools 6.0; macOS 14 / iOS 17 / watchOS 10): no UI. `AnthropicClient`
  (request build + parse, `HTTPTransport` seam), `PromptBuilder`, `Preset` / `PresetLibrary`, `ModelCatalog`,
  `WriteMyWay`, `WartimePeacetime`, `TextCleanup`, `KeyCombo`, `ShortcutConflicts`, `Languages`. Tests: 6 files, 107 tests.
- **`App/PerMyLast.xcodeproj`** (target `PerMyLast`): SwiftUI + AppKit menu bar app. Bundle ID `app.permylast`, version 1.0.0,
  macOS 14.0, Swift 5 language mode, sandbox on with only `network.client`, ad-hoc signed (`CODE_SIGN_IDENTITY = -`, no team).
  The app target has **no tests**.
- Key app files: `AppModel.swift` (482 lines, single `@Observable` model: settings, presets, send), `MainView.swift`,
  `SettingsView` + General/Advanced/Presets views, `WindowCoordinator`, `StatusItemController`, `Persistence.swift`.
- No `.github`, no CI, no git remote, no `backend/`, no `.env` / xcconfig handling.

## 2. Existing AI flow

- `AppModel.send()` / `sendAsk()` build a `ClaudeRequestContent` (system + content) **on the client** from the user's
  *editable* preset prompt, reply intent, `{{motherLanguage}}`, and Write My Way, then call `AnthropicClient.process` / `.ask`.
- `AnthropicClient`: one non-streaming `POST /v1/messages`, returns the first text block. Sends `x-api-key`, version
  `2023-06-01`, optional `anthropic-workspace-id`, and `output_config.effort` (skipped for Haiku 4.5).
  `maxTokens` 1024, Ask 4096. Default model `claude-sonnet-5`.
- Key storage: `UserDefaults["anthropicAPIKey"]`, **deliberately not Keychain** (commit `4cf0c43`).
- Persistence: JSON in `UserDefaults` (`Persistence.swift`). No sign-in, accounts, entitlements, paywall, or purchase code exists.
- Distribution today: unsigned/ad-hoc local builds; "Check for Updates" is a placeholder alert.

## 3. Proposed placement of new modules

| Module | Where | Notes |
|---|---|---|
| `AIClient` protocol, `AIRunRequest`, typed `AIError`, `DirectAnthropicClient` (streaming), `ProxyClient`, SSE parser, `Entitlement` / plan resolution, `AIClientFactory` logic, template model + renderer | `PerMyLastCore` (new files) | Pure and testable; keeps iOS/watch reuse; follows the existing `HTTPTransport` seam |
| `EntitlementStore`, `AuthService`, `KeyStore` (Keychain), `PurchaseService`, `TemplateStore` (disk cache), usage meter, paywall, key-setup views | `App/PerMyLast/` | Needs AppKit/SwiftUI/StoreKit/Keychain |
| Config | `AppConfig.swift` (app) and `backend/config.ts` | One place each, per PRD |
| Backend | `/backend` (Supabase migrations + edge functions) | Phase 2 |
| Tests | Core tests as today; **add an app test target** if Phase 1+ puts logic in the app | Currently none |

## 4. Conflicts and risks to resolve

1. **Keychain (FR-A12) vs the earlier decision to leave it.** The key moved out of Keychain on purpose (`4cf0c43`).
   The PRD requires Keychain-only. Ad-hoc signing makes Keychain prompt or fail on rebuilds; a real Developer ID / Mac App
   Store signature fixes that. *Need your call (see Questions).* A one-time migration from UserDefaults is required either way.
2. **Editable prompts vs server-side templates (FR-A1, A5, B4).** Today users edit prompts, add presets, and use a free-form
   Ask tab; the client assembles the final prompt. The PRD's proxy accepts only `template_id + variables` and never a raw
   system prompt or model. So on trial/Pro, **user-edited presets and the Ask tab cannot run unchanged**. Options in Questions.
3. **Streaming (FR-A2).** The current client is non-streaming and returns a `String`; the UI shows the result at the end.
   Streaming means a new client plus UI changes in `AppModel` / `MainView` (output grows as it arrives).
4. **Model and settings.** The app lets users pick model and effort and set a workspace ID. The PRD takes the model from the
   template (proxy). BYOK may keep model/effort/workspace; the proxy ignores them. Default `claude-sonnet-5` is
   far above the PRD's "Haiku-class" cost assumption, which matters for the 50-credit trial and Pro pricing. Template models
   need a decision before Phase 3.
5. **Token caps.** Ask uses 4096 output tokens; the PRD suggests `MAX_OUTPUT_TOKENS` ≈ 1024. Proxy runs of Ask would be capped.
6. **`sk-ant-` secret scan (NFR-1, AC-12).** The UI already contains `sk-ant-` as placeholder text and validation
   (`GeneralSettingsView`, `AppModel.apiKeyLooksInvalid`), and `Localizable.xcstrings`/tests may too. The scan must match
   key-shaped strings (e.g. `sk-ant-[A-Za-z0-9_-]{20,}`) or allowlist those files. Also, the repo has no CI yet.
7. **Two sales channels.** StoreKit 2 and Lemon Squeezy both feed `entitlements`. Mac App Store rules limit steering users
   to outside purchases from inside the MAS build, and offering third-party sign-in (Google) alongside Apple sign-in has its
   own review rules. Plan: build channel-specific purchase UI (MAS build shows StoreKit only; direct build shows Lemon Squeezy
   only) behind a build flag. Lemon Squeezy is a merchant of record with built-in license keys, which fits FR-P4. The PRD says
   "Paddle" in several places; read as Lemon Squeezy.
8. **Signing and capabilities.** StoreKit, Sign in with Apple and Keychain need a real team ID and entitlements
   (`applesignin`, possibly `keychain-access-groups`); not possible with the current ad-hoc setup. I can only prepare these
   and list the Apple Developer steps; I won't touch App Store Connect or Lemon Squeezy settings.
9. **Single-model size.** `AppModel` is already 482 lines; add new state in separate `@Observable` stores instead of growing it.
10. **Settings persistence is tolerant-decoded.** New settings fields must follow the same pattern (`decodeIfPresent`).

## 5. Questions that block Phase 1

1. **Key storage:** move the BYOK key to the Keychain (PRD) with a one-time migration, accepting prompts/failures until the
   app is properly signed? Or keep UserDefaults until signing is sorted?
2. **Prompts on the proxy:** (a) built-in presets only go through the proxy via server templates, and edited/custom presets
   and Ask require your own key; (b) the proxy also accepts a user-supplied prompt string with server-side caps (weakens FR-B4
   and abuse protection); (c) drop prompt editing for trial/Pro. Phase 1 (BYOK) is unaffected, so this can wait until Phase 2/3,
   but it shapes the `AIClient` signature.

## 6. Phase 1 plan (not started)

FR-A1, A2, A5, A6 (bundled templates only), A10–A12: add `AIClient` + streaming `DirectAnthropicClient` in Core, a bundled
templates JSON for the built-in presets, route `AppModel.send` through the protocol, Keychain `KeyStore`, key-setup screen with
"Test key", and tests. Exit: AC-6 (minus purchase), AC-7.
