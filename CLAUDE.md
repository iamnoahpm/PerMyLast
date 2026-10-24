# gstack

Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools directly.

Available gstack skills: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/design-shotgun`, `/design-html`, `/review`, `/ship`, `/land-and-deploy`, `/canary`, `/benchmark`, `/browse`, `/connect-chrome`, `/qa`, `/qa-only`, `/design-review`, `/setup-browser-cookies`, `/setup-deploy`, `/setup-gbrain`, `/retro`, `/investigate`, `/document-release`, `/document-generate`, `/codex`, `/cso`, `/autoplan`, `/plan-devex-review`, `/devex-review`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`, `/learn`, `/spec`, `/context-save`, `/context-restore`, `/ios-qa`, `/ios-fix`, `/ios-design-review`, `/ios-sync`, `/ios-clean`.

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior (website, website-v2) → invoke /qa or /qa-only
- Native app QA on device/simulator → invoke /ios-qa; fixing the bugs it finds → /ios-fix
- Native app visual audit → invoke /ios-design-review
- Code review/diff check → invoke /review
- Visual polish (website) → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec

## Project notes

- This is the native Swift rewrite (`App/`, `Packages/PerMyLastCore`); the Electron app lives on branch `electron-legacy`. Feature status is tracked in `docs/PARITY.md`.
- Logic tests: `cd Packages/PerMyLastCore && swift test`. Build steps are in `README.md`.
- Never deploy the website (permylast.app) until the user explicitly says so; preview locally first.
- Before a store build, remove the `captureLog` diagnostics from `AppModel.swift`.
