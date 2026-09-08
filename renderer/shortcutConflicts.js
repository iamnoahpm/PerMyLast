// Known-conflict database for the Global Shortcut recorder. Two tiers:
//  - "system": macOS-level shortcuts. A match here is a hard block — some of
//    these (Spotlight, screenshots) are intercepted by macOS before any app
//    ever sees the keydown, so the recorder can't always even capture them,
//    but the ones that do reach an app (Cmd+Q, Cmd+H, Cmd+,, etc.) are worth
//    guarding against explicitly.
//  - "app": shortcuts owned by specific common apps, not the OS itself. A
//    match here can't be a hard block (it's app-specific, not universal —
//    plenty of users won't run that app), so it's advisory only: shown as an
//    inline note while recording, and as a standing warning banner in the
//    main popup for whatever shortcut is currently saved.
const MACOS_SYSTEM_SHORTCUTS = [
  { accelerator: 'Command+Space', description: "macOS's Spotlight Search" },
  { accelerator: 'Command+Tab', description: "macOS's App Switcher" },
  { accelerator: 'Command+Shift+3', description: "macOS's screenshot (entire screen)" },
  { accelerator: 'Command+Shift+4', description: "macOS's screenshot (selection)" },
  { accelerator: 'Command+Shift+5', description: "macOS's screenshot/screen recording tools" },
  { accelerator: 'Command+Q', description: "the standard \"Quit\" shortcut" },
  { accelerator: 'Command+H', description: "the standard \"Hide\" shortcut" },
  { accelerator: 'Command+M', description: "the standard \"Minimize\" shortcut" },
  { accelerator: 'Command+W', description: "the standard \"Close Window\" shortcut" },
  { accelerator: 'Command+,', description: "the standard \"Preferences\" shortcut" },
  { accelerator: 'Command+Option+Escape', description: "macOS's Force Quit dialog" },
  { accelerator: 'Control+Command+Q', description: "macOS's Lock Screen" },
  { accelerator: 'Control+Up', description: "macOS's Mission Control" },
  { accelerator: 'Control+Down', description: "macOS's App Exposé" }
];

const COMMON_APP_SHORTCUTS = [
  { accelerator: 'Command+Shift+S', app: 'TextEdit, Preview, Pages', description: '"Duplicate" / "Save As"' },
  { accelerator: 'Command+Shift+N', app: 'Chrome and most browsers', description: '"New Incognito/Private Window"' },
  { accelerator: 'Command+Shift+T', app: 'Chrome and most browsers', description: '"Reopen Closed Tab"' }
];

const SHORTCUT_MODIFIER_ORDER = ['Control', 'Alt', 'Shift', 'Command'];
const SHORTCUT_MODIFIER_SYMBOLS = { Control: '⌃', Alt: '⌥', Shift: '⇧', Command: '⌘' };

// e.g. "Control+Command+Shift+S" -> "⌃⌘⇧S" (Apple's canonical HIG symbol order)
function acceleratorToDisplay(accelerator) {
  const parts = accelerator.split('+');
  const key = parts.pop();
  const mods = SHORTCUT_MODIFIER_ORDER.filter((m) => parts.includes(m)).map((m) => SHORTCUT_MODIFIER_SYMBOLS[m]);
  return mods.join('') + key;
}

function normalizeAccelerator(accelerator) {
  return accelerator.split('+').map((p) => p.trim().toLowerCase()).sort().join('+');
}

// scope: 'system' | 'app' | undefined (checks both)
function findShortcutConflict(accelerator, scope) {
  const target = normalizeAccelerator(accelerator);
  const candidates = [];
  if (scope !== 'app') candidates.push(...MACOS_SYSTEM_SHORTCUTS.map((s) => ({ ...s, scope: 'system' })));
  if (scope !== 'system') candidates.push(...COMMON_APP_SHORTCUTS.map((s) => ({ ...s, scope: 'app' })));
  return candidates.find((c) => normalizeAccelerator(c.accelerator) === target) || null;
}

if (typeof window !== 'undefined') {
  window.ShortcutConflicts = { MACOS_SYSTEM_SHORTCUTS, COMMON_APP_SHORTCUTS, findShortcutConflict, acceleratorToDisplay };
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { MACOS_SYSTEM_SHORTCUTS, COMMON_APP_SHORTCUTS, findShortcutConflict, acceleratorToDisplay };
}
