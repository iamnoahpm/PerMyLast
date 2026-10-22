# Port these changes from the native app to the Electron app (v1.1.0 → next)

Paste this file (and the PNGs next to it) into a Claude session opened on the
Electron repo (`iamnoahpm/PerMyLast`, branch `electron-legacy`).

## 1. Logo / icons

Files in this folder:

| File | Use |
|---|---|
| `app-icon-1024.png` | App / Dock icon (generate `.icns` / `.ico` from it) |
| `tray-enabled.png` (18px), `tray-enabled@2x.png` (36px) | Tray icon when the app is **enabled**: solid open umbrella |
| `tray-disabled.png`, `tray-disabled@2x.png` | Tray icon when **disabled**: outlined, tilted umbrella |

- Tray images are single-colour template images (black + alpha). On macOS use
  `nativeImage.createFromPath(...)` then `image.setTemplateImage(true)` so they tint for
  light/dark menu bars. Name them `...Template.png` if you rely on Electron's auto-template.
- Swap the tray image whenever "Enabled" is toggled (replaces the old plain dot).

## 2. Tray (menu bar) behaviour

- **Left-click**: open the app (popup; Settings if no API key is saved yet).
- **Right-click / Control-click**: show the menu. Do not attach the menu with
  `tray.setContextMenu` (that makes left-click open it too); use
  `tray.popUpContextMenu(menu)` on the `right-click` event.
- Menu items, in order, with separators as shown. There is **no** "Open Per My Last" item:
  1. Enabled (checkbox)
  2. Show in Dock (checkbox)
  3. ———
  4. Settings… (⌘,)
  5. Check for Updates…
  6. ———
  7. Quit Per My Last (⌘Q)
- **Show in Dock** is a new setting (also in Settings → General): on by default; off = menu-bar-only
  (`app.dock.hide()` / `app.dock.show()`). Clicking the Dock icon opens the popup (Settings if no key).
  Closing windows keeps the app running.
- **Check for Updates…** moves out of the popup and Settings footers into this menu.

## 3. Other changes since v1.1.0 worth porting

- Settings → General: the Feedback form is removed; the popup footer keeps "Send feedback" (mailto).
- Popup and Settings behave as normal windows; popup docks to the right half of the screen.
- **Write tab defaults**: "Rewrite like Native" → **Like Brit.** (🤴), "Rewrite Like Me" → **Like Me** (🫆);
  Fix Grammar and Professional dropped. Both rewrite as a casual Teams message
  (fix grammar, phrasing, flow only; content intact; line breaks only where they help; no em dashes);
  Like Brit. adds native English. Migrate saved copies unless the user edited them.
- **Write My Way** now feeds the prompts (it was a mockup): tone / length / format (+ English level for Like Me)
  are appended to any action with "Use my Write My Way settings" on. Defaults: casual / short / message.
- New default prompts for Email and Message with template slots; Email Reply uses the full drafting prompt.
- **Explain / Translate** prompts reworded (no em dash in output). Translate:
  "Translate this into {{motherLanguage}}. Don't ever use "—" in the output."
- **New Ask tab**: fixed last tab, not a preset. One "Your question" box sent straight to the model with a
  general-assistant system prompt and a 4096-token limit; can't be renamed or removed.
- **Tone Presets editor**: tabs along the top (Edit tabs popover: add, rename, delete, drag to reorder);
  action list on the left (default starred), focused editor on the right (icon, name, tone, description,
  prompt with Edited / Reset to original, Write My Way toggle, default, delete). Autosaves; no Save button.
- Mother language row shows "flag name" at the right edge, like App Language.
- API key stored in app preferences instead of the Keychain.
- Vietnamese UI via a string catalog with an in-app language switch.

Full checklist: `docs/PARITY.md`.
