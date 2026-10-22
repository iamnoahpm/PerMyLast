# Per My Last design system: handoff for the native app

Goal: restyle the native SwiftUI app (`/Users/macos/Developer/PerMyLast`) to the Per My Last design system, light and dark, without changing behaviour. The hosted, browsable version is the Per My Last Design System artifact (https://claude.ai/artifact/8XD4FSwWxNfCcgaH26PRDx, private to the owner).

## What is in this folder

| File | Use |
| --- | --- |
| `DESIGN-SYSTEM.md` | The brand book: voice, colour, type, space, shape, motion, states, icons. Read first. |
| `tokens.json` | Source of truth for every value (colours in light and dark, type styles, spacing, radius, shadow, layout). |
| `DesignTokens.swift` | Generated Swift: `PMLColor`, `PMLSpace`, `PMLRadius`, `PMLLayout`, `PMLFont`, `PMLShadow`, `PMLMotion`. Add to the app target; do not edit by hand. |
| `SwiftUI.md` | Token and component mapping to SwiftUI, and the build rules. |
| `components/<Name>/README.md` | Usage rules per component: Window, ModeRail, PresetChip, Field, Button, OutputPanel, Banner, TrayMenu. |
| `reference/*.html` | Open in a browser: each component in light and dark, plus the Cover. Same CSS as the system. |
| `assets/` | App icon (1024px) and the four menu bar icons (template images, 18px and 36px). |

## Order of work

1. Add `DesignTokens.swift` to `App/PerMyLast.xcodeproj`. Bundle Plus Jakarta Sans (OFL, Google Fonts, variable TTF) and register it with `ATSApplicationFontsPath`. Add the light and dark colours check in a SwiftUI preview.
2. Build the shared pieces as small views and `ButtonStyle`s in one new file: `PMLPrimaryButtonStyle`, `PMLSecondaryButtonStyle`, `PMLGhostButtonStyle`, `PMLChipStyle`, `PMLField`, `PMLPanel`. Follow `components/*/README.md` for exact fills, radii and states.
3. Restyle the popup in `MainView.swift`: replace the segmented `Picker` in `tabs(selection:)` with a `ModeRail` (tab strip below `PMLLayout.railBreakpoint` points, left rail at or above it), restyle `chips`, `PromptPanel`, `inputBox`, `askBox`, `intentRow`, `sendRow`, `OutputPanel`, `FooterBar` and both banners.
4. Menu bar: swap in the umbrella template icons and make left-click open the popup, right-click show the menu (Enabled, Show in Dock, Settings…, Check for Updates…, Quit Per My Last). See `components/TrayMenu/README.md`. Edit `StatusItemController.swift`.
5. Settings (`SettingsView`, `GeneralSettingsView`, `AdvancedSettingsView`, `PresetsSettingsView`), then `PaywallView` and `AccountViews`: same tokens, rows on `surface` with `divider` hairlines, one `accent` fill per view.
6. Window behaviour in `WindowCoordinator.swift` stays: dock to the right half of the screen, re-dock on show, minimum size `PMLLayout.popupMinWidth` by `popupMinHeight`.

## Do not change

Behaviour, copy keys and Localizable.xcstrings strings, the Ask tab rules, presets, Write My Way, the credits badge, shortcuts. This is a visual and layout change. Where the existing Vietnamese strings are longer, let layouts wrap instead of truncating.

## Done when

- No colour literal, system grey or `Color.accentColor` remains in app views; everything resolves through `PMLColor`. No font size outside `PMLFont`.
- Light and dark both checked at 380pt, 640pt and half-screen width; the rail appears at 640pt.
- Send is the only `accent`-filled control in each view; disabled Send explains itself in a tooltip.
- Keyboard focus rings are visible; arrow keys move between modes; Reduce Motion removes the hover lift.
- `swift test` in `Packages/PerMyLastCore` still passes and the app builds with the command in the repo README.

## Prompt to paste into a session on the native repo

> Read `design_handoff_native_app/README.md`, then `DESIGN-SYSTEM.md`, `SwiftUI.md` and the component READMEs. Restyle the macOS app to this design system in the order listed, one commit per step: tokens and fonts, shared styles, popup, menu bar, settings, paywall. Keep behaviour and localisation unchanged. Run the app after each step and check light and dark.

## Known gaps in the system

- `ink-hint` (placeholders) is 2.8:1 on `surface`; it is flagged as placeholder-only.
- Dark-theme values are new (the Electron app was light only); review them on a real display.
- Only the Latin Plus Jakarta Sans subset is in `reference/`; the app needs the full variable TTF for Vietnamese.
- Not yet specified: the Tone Presets editor, Settings pages and Paywall as full screens, and the iPhone layout. They follow the same tokens; add component pages when you redesign them.
