# Feature: Global Capture-and-Fill Shortcut

## What
While the user has text selected in any app (Chrome, Slack, Teams, etc.), pressing a global keyboard shortcut copies that selection and fills it directly into a fixed textbox inside our Electron app, bringing our app to the front in the process.

## Why
Lets users pull text from anywhere on the Mac into our app without manually switching apps, copying, switching back, and pasting.

## Behaviour
- Global shortcut (default `Cmd+Shift+V`, user-configurable later) registered via Electron's `globalShortcut` module. Works system-wide, regardless of which app is focused, as long as our app is running (foreground or background).
- On trigger:
  1. Read the name of the current frontmost application (via `osascript`/System Events) before doing anything else.
  2. If the frontmost app **is** our own app, no-op (nothing to capture from).
  3. Simulate `Cmd+C` in the frontmost app (via `osascript System Events keystroke "c" using command down`).
  4. Wait a short fixed delay (~150ms) for the OS clipboard to update, then read `clipboard.readText()`.
  5. Bring our app's window to the front (`app.focus()` / restore if minimized).
  6. Send the captured text to the renderer via IPC and set it directly into the fixed target textbox's value (not by simulating `Cmd+V` — we already have the string, so we bypass a second paste step).
  7. Focus the textbox and place cursor at the end.
- Overwrites the textbox's existing content by default (not appended).
- If the clipboard content is unchanged after the simulated copy (nothing was selected in the source app), do nothing: no window switch, no textbox change, no error dialog.
- Preserves the user's pre-existing clipboard content: after step 4 completes, restore the clipboard to whatever it held immediately before step 3 (so we don't clobber something the user had copied earlier). Restoration happens after our own IPC write, so it doesn't race with step 6.
- Requires macOS Accessibility permission (System Settings → Privacy & Security → Accessibility) for the app, since simulating keystrokes and activating other apps both need it.
  - If permission is missing, the shortcut trigger shows a one-time native dialog directing the user to the Accessibility settings pane, and does not attempt steps 3–7.
- If our app's window doesn't exist yet (fully quit, not just backgrounded), the shortcut still works if the app has a background/tray process registered — otherwise this feature requires the app to be running.

## Acceptance Criteria
```gherkin
Scenario: Happy path from a third-party app
  Given Slack is frontmost and the user has text selected
  When the user presses the global shortcut
  Then our app's window comes to front
  And the fixed target textbox contains exactly the selected text
  And the user's previous clipboard content is restored after the fill

Scenario: No selection in source app
  Given Chrome is frontmost with no text selected
  When the user presses the global shortcut
  Then our app's window does not come to front
  And the target textbox is unchanged

Scenario: Triggered while our own app is frontmost
  Given our app is already the frontmost application
  When the user presses the global shortcut
  Then no copy/paste simulation occurs
  And the target textbox is unchanged

Scenario: Accessibility permission not granted
  Given the app does not have macOS Accessibility permission
  When the user presses the global shortcut
  Then a native dialog directs the user to System Settings > Privacy & Security > Accessibility
  And no keystroke simulation or app activation is attempted
```

## Open Questions (confirm before build)
- Exact default shortcut key combo, and whether it needs to be user-remappable in v1. (assume `Cmd+Shift+V`, fixed for v1, remappable later)
- Behaviour when the fixed target textbox already has unsaved content the user typed manually — overwrite silently, or confirm? (assume overwrite silently, per Behaviour above)
- Whether the feature should work when the app is fully quit (requires a persistent background/tray process + `app.setLoginItemSettings` or similar) or only while at least backgrounded. (assume "running in background" is the minimum bar, not "fully quit")

## Telemetry
- `global_capture_shortcut_triggered { source_app, success: bool, reason?: 'no_selection' | 'own_app_frontmost' | 'missing_permission' }` — flag as open question if the product's telemetry pipeline isn't wired up for main-process (non-renderer) events yet.

## Done When
AC pass · works from Chrome, Slack, and Teams as source apps · clipboard is restored after every successful fill · Accessibility-permission-missing path shows the dialog and performs no simulation · no regression to existing global shortcuts or clipboard-dependent features.

---
**Stack notes for implementation (Electron / macOS):**
- `globalShortcut.register()` in the main process for the hotkey.
- `child_process.exec` or `execFile` running `osascript` for (a) getting the frontmost app name, (b) simulating `Cmd+C`, (c) activating our app. Wrap all AppleScript calls in a small helper module so they're mockable in tests.
- `clipboard` module (Electron) for read/write/restore.
- `ipcMain.on` / `webContents.send` to push the captured text to the renderer; renderer sets the textbox value via its existing state management and focuses it.
- Consider `systemPreferences.isTrustedAccessibilityClient(false)` to check Accessibility permission before attempting the AppleScript steps, and `isTrustedAccessibilityClient(true)` to prompt if not granted.

I can also emit the Acceptance Criteria above as a standalone `.feature` file if your test runner (e.g. Cucumber, Playwright-BDD) consumes Gherkin directly — let me know.
