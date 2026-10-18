# Feature parity: Electron app (v1.1.0) vs native app

Source of truth for the old behaviour: branch `electron-legacy` (`main.js`,
`presets.js`, `renderer/index.html`, `renderer/settings.html`, `renderer/i18n.js`).
Status: ✅ done · 🟡 partial · ⬜ missing · ➖ intentionally different

## Popup (main window)

| # | Feature | Status |
|---|---|---|
| 1 | Tabs (Reply / Write / Understand, user-defined), preset chips with icon + blurb | ✅ |
| 2 | Chips: keyboard navigation (arrow keys) | ✅ |
| 3 | Reply-intent field on tabs that take intent, Send beside it | ✅ |
| 4 | Source textbox, word count, ⌘↩ to send, Esc to hide | ✅ |
| 5 | Text clean-up (`beautifyText`) on captured text, pasted text and results | ✅ |
| 6 | **Prompt panel**: collapsible, shows resolved prompt + tone | ✅ |
| 7 | Edit prompt in place, "Save & overwrite", "Reset to original", "Edited" state, "Saved to … › …" flash | ✅ |
| 8 | Mother-language missing → inline "set it in Settings" link, Send disabled with tooltip | ✅ |
| 9 | Output panel: empty-state hint, result header (label · tone), Copy → "Copied!" | ✅ |
| 10 | Regenerate, Send again, error box with Retry | ✅ |
| 11 | Footer: version, Send feedback (mailto), Check for updates | ✅ |
| 12 | Header eyebrow "What are you trying to do?" + tagline | ✅ |
| 13 | Shortcut-conflict warning banner (with Settings / Dismiss) | ✅ |
| 14 | Popup opens on launch when an API key exists | ✅ |
| 15 | Docked to right half of the screen, full height; re-docked on every show | ✅ |
| 16 | Popup text updates live when presets/tabs change in Settings | ✅ (shared model) |

## Settings

| # | Feature | Status |
|---|---|---|
| 20 | API key (Keychain), "Get one at console.anthropic.com" link, `sk-ant-` validation | ✅ |
| 21 | Workspace ID + hint | ✅ |
| 22 | Model picker + custom model + "Selected model", effort levels + hints/notes | ✅ |
| 23 | **Global shortcut recorder** (click, press combo, Esc cancels, clear) | ✅ |
| 24 | Shortcut conflict detection: macOS system list + per-app list, blocks save for system conflicts | ✅ |
| 25 | Show in Dock, Launch at login (with hints) | ✅ |
| 26 | Mother language (searchable, flags) | ✅ |
| 27 | App language: English (US/UK) + Vietnamese, applied to the whole UI | ✅ |
| 28 | Feedback form → opens mail client | ✅ |
| 29 | Explicit Save with "Saved! Using {model}" confirmation, validation errors | ➖ (autosave + "Saved" flash; API key and shortcut are validated as you type) |
| 30 | **Tone Presets tab**: add / rename / delete / reorder tabs | ✅ |
| 31 | Edit presets: name, icon, blurb, tone, prompt; default star; delete; drag to reorder; "used N times"; "+ Add to {tab}" | ✅ |
| 32 | Intent-takes-a-tab setting (`intentModes`) kept in sync on rename/delete | 🟡 (model only, not editable) |
| 33 | Permissions tab (Accessibility / Automation status) | ➖ (not needed in clipboard mode) |
| 34 | Advanced → Tools list (Write My Way, VIP Contacts, Wartime/Peacetime) | ✅ |
| 35 | Wartime / Peacetime: enable toggle, mode picker, compare modes, "Copy context for an AI assistant" | ✅ |
| 36 | Write My Way (English level, writing style) — *mockup only in Electron* | ✅ |
| 37 | Settings opens in place of the popup, restores it on close | ✅ |

## App / system

| # | Feature | Status |
|---|---|---|
| 40 | Menu bar item: Enabled toggle, Open, Show in Dock, Settings, Quit | ✅ |
| 41 | Dock icon, click Dock icon → popup, closing windows keeps app running | ✅ |
| 42 | Auto-capture of selected text (Cmd+C via System Events) | ➖ (DMG-only in Electron; native Accessibility version planned) |
| 43 | Anthropic request: effort, workspace header, max tokens, error surfacing | ✅ |
| 44 | Per-preset usage counter | ✅ |
| 45 | Check for updates | ➖ (Electron: placeholder dialog) |

## Known Electron bugs not carried over

- Saving an edited prompt from the popup dropped `requiresMotherLanguage` on the
  Translate preset (the IPC payload never included it).

## Native-only notes

- Display order of shortcut symbols follows Apple's HIG (⌃⌥⇧⌘), so ⌘⇧W shows as ⇧⌘W.
  (The Electron code's comment claimed ⌃⌘⇧ but its code produced the same order.)
- Write My Way is a preview, exactly like the Electron one: choices are saved but not yet used in prompts.
- Vietnamese UI strings live in `App/PerMyLast/Localizable.xcstrings`; the wording reuses the Electron app's.
  Shortcut-conflict descriptions and the Wartime/Peacetime content stay English (as before).
