const { app, BrowserWindow, globalShortcut, ipcMain, Tray, Menu, clipboard, nativeImage, screen, shell, net, systemPreferences, dialog } = require('electron');
const Store = require('electron-store');
const path = require('path');
const { execFile } = require('child_process');
const { DEFAULT_MODES, DEFAULT_PRESETS, validateLabel, normalizePresets, upsertPreset, deletePreset, incrementUses, applyPresetEdits, addMode, renameMode, deleteMode, reorderModes, buildClaudeRequest } = require('./presets');
const { findShortcutConflict } = require('./renderer/shortcutConflicts');

// Distinguishes a dev/test run from the packaged app installed from the DMG —
// otherwise both show "Per My Last" in the Dock/menu bar with no way to tell
// which is which when testing alongside a real install. Also gives dev a
// separate store file so the two don't read/write the same settings out from
// under each other while both are running.
if (!app.isPackaged) app.setName('PerMyLast (dev)');

const store = new Store(app.isPackaged ? {} : { name: 'config-dev' });
const DEFAULT_MODEL = 'claude-sonnet-5';
const DEFAULT_EFFORT = 'medium';
const EFFORT_LEVELS = ['low', 'medium', 'high', 'xhigh', 'max'];
// output_config.effort is rejected outright by Haiku 4.5 (an older-tier
// model) — a custom "Other" model string is left unchecked here since its
// capability can't be known at settings-save time; the renderer shows a
// caveat instead.
const EFFORT_UNSUPPORTED_MODELS = ['claude-haiku-4-5'];
const SUPPORTED_APP_LANGUAGES = ['en-US', 'en-GB', 'vi'];
const FEEDBACK_EMAIL = 'iamnoahpm@gmail.com';

// Only English and Vietnamese UI strings exist right now — default to
// Vietnamese only if that's genuinely the Mac's own language, English for
// every other system locale (matches "if not then default English").
function detectDefaultAppLanguage() {
  return app.getLocale().toLowerCase().startsWith('vi') ? 'vi' : 'en-US';
}
// Command+Shift+S collides with the "Save As"/"Duplicate" menu shortcut in
// TextEdit, Preview, Pages, and many other apps, plus assorted browser
// extensions (screenshot tools especially default to it) — when the
// frontmost app has a local menu item on the same combo, it can win the race
// and swallow the keystroke before our global shortcut ever fires, which
// looks like "the hotkey needs two presses." Command+Shift+W isn't in either
// known-conflict list in shortcutConflicts.js, but as a 3-key combo it's
// worth re-checking there if it ever turns out to collide with something.
const DEFAULT_SHORTCUT = 'Command+Shift+W';
const LEGACY_DEFAULT_SHORTCUT = 'Command+Shift+S';
let mainWindow = null;
let settingsWindow = null;
let tray = null;
let isEnabled = true;

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 440,
    height: 580,
    show: false,
    frame: false,
    transparent: true,
    resizable: true,
    minWidth: 360,
    minHeight: 420,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.js')
    }
  });

  mainWindow.loadFile('renderer/index.html');

  mainWindow.on('close', (e) => {
    if (!app.isQuitting) { e.preventDefault(); mainWindow.hide(); }
  });

  // Whatever's currently saved might be a known third-party-app conflict
  // (advisory only — unlike a macOS system conflict, this can't be blocked
  // at save time since it depends on apps the user may or may not even run).
  // Re-checked on every show rather than once, so fixing it in Settings and
  // reopening the popup clears the warning without needing a reload.
  mainWindow.on('show', () => {
    const conflict = findShortcutConflict(store.get('shortcut', DEFAULT_SHORTCUT), 'app');
    mainWindow.webContents.send('shortcut-conflict-status', conflict);
    // The popup only ever fetched this once at page load, so setting it in
    // Settings and coming back (Settings hides this window rather than
    // reloading it) left the "set your mother language" prompt link showing
    // even after it was set — re-push it on every show instead.
    mainWindow.webContents.send('mother-language-status', store.get('motherLanguage', ''));
    // Same reasoning — switching App Language in Settings should take effect
    // the moment you're back at the popup, not after a relaunch.
    mainWindow.webContents.send('app-language-status', store.get('appLanguage', detectDefaultAppLanguage()));
  });
}

function createSettingsWindow(bounds) {
  if (settingsWindow) { settingsWindow.focus(); return; }
  settingsWindow = new BrowserWindow({
    x: bounds.x,
    y: bounds.y,
    width: bounds.width,
    height: bounds.height,
    frame: false,
    transparent: true,
    resizable: true,
    minWidth: 360,
    minHeight: 420,
    title: 'PerMyLast Settings',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.js')
    }
  });
  settingsWindow.loadFile('renderer/settings.html');
  settingsWindow.on('closed', () => {
    settingsWindow = null;
    // Safety net: if the window closed mid-recording (e.g. the user hit the
    // close button instead of Escape), the shortcut recorder's own suspend
    // would never get its matching resume — re-registering here guarantees
    // the real hotkey is always live again once Settings is gone.
    registerShortcut();
    // Settings replaces the assistant popup in place while open — bring it
    // back once Settings closes, rather than leaving it hidden.
    if (mainWindow) mainWindow.show();
  });
}

// Settings opens at the exact position/size the assistant popup currently
// occupies (or the same docked layout it would use, if it isn't open right
// now), replacing it in place rather than popping up somewhere else.
function openSettingsWindow() {
  const bounds = (mainWindow && mainWindow.isVisible()) ? mainWindow.getBounds() : computeDockedBounds();
  if (mainWindow && mainWindow.isVisible()) mainWindow.hide();
  createSettingsWindow(bounds);
}

// Simulates Cmd+C via System Events so the hotkey works on whatever text is
// currently selected in the frontmost app, without requiring a manual copy
// first. This needs two separate one-time OS grants: Automation permission
// (this app controlling "System Events") and Accessibility permission —
// macOS prompts for both the first time this runs; if either is denied,
// osascript exits non-zero and we fall back to reading the clipboard as-is.
function simulateCopy() {
  return new Promise((resolve) => {
    execFile('osascript', ['-e', 'tell application "System Events" to keystroke "c" using command down'], (err, stdout, stderr) => {
      resolve({ ok: !err, error: err ? (stderr || err.message) : null });
    });
  });
}

// Electron exposes a direct, side-effect-free check for Accessibility.
// There's no equivalent for Automation, so we probe it with a query that
// needs Automation to reach System Events at all (an Apple Events
// permission) but doesn't touch UI elements, so it can't accidentally send a
// keystroke into whatever app happens to be frontmost when this runs.
function checkAccessibilityGranted() {
  return systemPreferences.isTrustedAccessibilityClient(false);
}

// Querying basic process info (name, frontmost) from System Events does NOT
// require Automation permission on macOS — only "controlling" actions like
// keystroke/click do. An earlier version of this check used a plain process
// query and always reported "Granted" even when Automation had never been
// requested. keystroke "" sends zero characters (no visible side effect —
// nothing typed, clipboard untouched) while still exercising the exact same
// permission gate as the real feature.
function checkAutomationGranted() {
  return new Promise((resolve) => {
    execFile('osascript', ['-e', 'tell application "System Events" to keystroke ""'], (err, stdout, stderr) => {
      if (!err) return resolve(true);
      const msg = stderr || err.message || '';
      // -1719 / "not allowed assistive access" means the call DID reach
      // System Events and only stalled on the Accessibility check inside
      // it — so Automation itself is fine; Accessibility is the blocker,
      // and that's reported separately via the native Electron API.
      if (/-1719|assistive access/i.test(msg)) return resolve(true);
      // Anything else (typically -1743 / "not authorized to send Apple
      // events") means Automation itself is the blocker.
      resolve(false);
    });
  });
}

// Forces the app to activate before showing the popup, so it reliably
// raises above whatever app currently has focus when triggered via the
// global hotkey (rather than only sometimes, depending on window-manager
// state). Bounds are (re-)applied after show(), not before — macOS has been
// observed to not fully commit a frameless transparent window's new bounds
// until it's actually visible, leaving it at a stale size otherwise.
function showMainWindow() {
  app.focus({ steal: true });
  mainWindow.show();
  positionWindow();
}

function getFrontmostAppName() {
  return new Promise((resolve) => {
    execFile('osascript', ['-e', 'tell application "System Events" to get name of first process whose frontmost is true'], (err, stdout) => {
      resolve(err ? null : stdout.trim());
    });
  });
}

// The hotkey fires regardless of which app is frontmost, including our own —
// e.g. the user is already in the popup and hits it out of habit. Simulating
// Cmd+C in that case would just copy from our own textarea, then overwrite it
// with itself, so it's simplest to treat "we're already frontmost" as
// nothing-to-capture and no-op entirely. Checked via the actual OS-level
// frontmost process (same query the spec calls for) rather than Electron's
// own getFocusedWindow(), which can keep reporting one of our windows as
// "focused" even after a different app has genuinely taken over — that stale
// state was making every capture attempt silently no-op after the first one.
// In a packaged build the frontmost name is the productName ("Per My Last");
// in dev (`npx electron .`) it's "Electron" — checking both covers either.
async function isOwnAppFrontmost() {
  const frontmost = await getFrontmostAppName();
  return frontmost === 'Per My Last' || frontmost === 'Electron';
}

// Both permissions gate the capture: Accessibility for the keystroke
// simulation itself, Automation for controlling "System Events" at all.
// Shown as a native dialog rather than the in-app banner, since at this point
// we haven't shown (and per spec shouldn't show) our window at all.
function notifyPermissionMissing({ accessibility, automation }) {
  const missing = [];
  if (!accessibility) missing.push('Accessibility');
  if (!automation) missing.push('Automation (control of "System Events")');

  dialog.showMessageBox({
    type: 'warning',
    buttons: ['Open System Settings', 'Cancel'],
    defaultId: 0,
    cancelId: 1,
    title: 'Permission Needed',
    message: `Per My Last needs ${missing.join(' and ')} to capture your selection.`,
    detail: 'Grant access in System Settings, then try the shortcut again.'
  }).then(({ response }) => {
    if (response !== 0) return;
    if (!accessibility) shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility');
    if (!automation) shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Automation');
  });
}

// Implements feature-global-capture-paste.md: capture whatever's selected in
// the frontmost app and fill it straight into the popup's textbox, without
// disturbing the user's clipboard.
async function captureAndFill() {
  if (!isEnabled) return;
  if (await isOwnAppFrontmost()) return;

  const [accessibility, automation] = await Promise.all([
    Promise.resolve(checkAccessibilityGranted()),
    checkAutomationGranted()
  ]);
  if (!accessibility || !automation) {
    notifyPermissionMissing({ accessibility, automation });
    return;
  }

  // clipboard.readText() is documented as synchronous but returns a Promise
  // in this Electron build — Promise.resolve() normalizes both cases, since
  // awaiting an already-plain string is a no-op.
  const previousClipboard = await Promise.resolve(clipboard.readText());

  const copyResult = await simulateCopy();
  if (!copyResult.ok) {
    // Permission was revoked between the check above and this call — rare,
    // but re-check fresh rather than assuming which one regressed.
    console.error('simulateCopy failed:', copyResult.error);
    const [freshAccessibility, freshAutomation] = await Promise.all([
      Promise.resolve(checkAccessibilityGranted()),
      checkAutomationGranted()
    ]);
    notifyPermissionMissing({ accessibility: freshAccessibility, automation: freshAutomation });
    return;
  }
  await new Promise((resolve) => setTimeout(resolve, 150));

  const capturedText = await Promise.resolve(clipboard.readText());
  // An unchanged clipboard means nothing was selected in the source app (Cmd+C
  // with no selection is a no-op) — do nothing rather than show stale content
  // left over from an earlier copy.
  if (capturedText === previousClipboard) return;

  showMainWindow();
  mainWindow.webContents.send('selected-text', capturedText);
  mainWindow.focus();
  clipboard.writeText(previousClipboard);
}

// Docks the window to the right edge of whichever display currently has the
// cursor, full height, width = 1/2 the screen. Re-applied on every show, not
// just once, so it stays consistent even if the user manually resized it
// last time.
function computeDockedBounds() {
  const pt = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(pt);
  const b = display.workArea;

  const width = Math.round(b.width / 2);
  const height = b.height;
  const x = b.x + b.width - width;
  const y = b.y;

  return { x, y, width, height };
}

function positionWindow() {
  mainWindow.setBounds(computeDockedBounds());
}

function createTray() {
  tray = new Tray(nativeImage.createEmpty());
  refreshTrayMenu();
  // No 'click' handler: with a context menu set, macOS shows that menu on
  // any click (left or right). A 'click' listener would instead intercept
  // left-clicks and skip straight to showing the popup, bypassing the menu —
  // "Open Per My Last" is already the first item for that.
}

function setShowInDock(value) {
  store.set('showInDock', value);
  if (!app.dock) return;
  if (value) app.dock.show(); else app.dock.hide();
}

// openAtLogin is the actual source of truth (macOS remembers it independent
// of our own store), so we always read it back after setting it rather than
// trusting the value we asked for — matches how app.dock.isVisible() could
// diverge from a stale stored showInDock, just for login items instead.
function setLaunchAtLogin(value) {
  app.setLoginItemSettings({ openAtLogin: !!value });
  store.set('launchAtLogin', app.getLoginItemSettings().openAtLogin);
}

function refreshTrayMenu() {
  const menu = Menu.buildFromTemplate([
    { label: isEnabled ? '✅ Enabled' : '❌ Disabled', click: () => { isEnabled = !isEnabled; store.set('isEnabled', isEnabled); refreshTrayMenu(); } },
    { type: 'separator' },
    { label: 'Open Per My Last', accelerator: store.get('shortcut', DEFAULT_SHORTCUT), click: showMainWindow },
    { label: 'Show in Dock', type: 'checkbox', checked: store.get('showInDock', true), click: (item) => { setShowInDock(item.checked); } },
    { label: 'Settings…', click: openSettingsWindow },
    { type: 'separator' },
    { label: 'Quit', accelerator: 'Command+Q', click: () => app.quit() }
  ]);
  tray.setContextMenu(menu);
  updateTrayIcon();
}

// Lit flame while enabled, unlit/outline flame while disabled — monochrome
// silhouettes, marked as template images so macOS auto-inverts them for
// light/dark menu bars, same as every other menu-bar icon.
function updateTrayIcon() {
  const file = isEnabled ? 'tray-enabled.png' : 'tray-disabled.png';
  const icon = nativeImage.createFromPath(path.join(__dirname, 'assets', file));
  icon.setTemplateImage(true);
  tray.setImage(icon);
}

function registerShortcut() {
  globalShortcut.unregisterAll();
  const sc = store.get('shortcut', DEFAULT_SHORTCUT);
  const ok = globalShortcut.register(sc, captureAndFill);
  if (!ok) console.error('Failed to register global shortcut:', sc, '— it may already be in use by another app.');
}

ipcMain.handle('get-settings', () => ({
  apiKey: store.get('apiKey', ''),
  model: store.get('model', DEFAULT_MODEL),
  effort: store.get('effort', DEFAULT_EFFORT),
  shortcut: store.get('shortcut', DEFAULT_SHORTCUT),
  workspaceId: store.get('workspaceId', ''),
  showInDock: store.get('showInDock', true),
  launchAtLogin: app.getLoginItemSettings().openAtLogin,
  wartimePeacetimeEnabled: store.get('wartimePeacetimeEnabled', false),
  motherLanguage: store.get('motherLanguage', ''),
  appLanguage: store.get('appLanguage', detectDefaultAppLanguage())
}));

ipcMain.handle('save-settings', (e, s) => {
  if (s.apiKey !== undefined) store.set('apiKey', s.apiKey);
  if (s.model !== undefined) store.set('model', s.model);
  if (s.effort !== undefined && EFFORT_LEVELS.includes(s.effort)) store.set('effort', s.effort);
  if (s.workspaceId !== undefined) store.set('workspaceId', s.workspaceId);
  if (s.wartimePeacetimeEnabled !== undefined) store.set('wartimePeacetimeEnabled', s.wartimePeacetimeEnabled);
  if (s.motherLanguage !== undefined) store.set('motherLanguage', s.motherLanguage);
  if (s.appLanguage !== undefined && SUPPORTED_APP_LANGUAGES.includes(s.appLanguage)) {
    store.set('appLanguage', s.appLanguage);
  }
  if (s.showInDock !== undefined && s.showInDock !== store.get('showInDock', true)) {
    setShowInDock(s.showInDock);
    refreshTrayMenu();
  }
  if (s.launchAtLogin !== undefined && s.launchAtLogin !== app.getLoginItemSettings().openAtLogin) {
    setLaunchAtLogin(s.launchAtLogin);
  }
  if (s.shortcut !== undefined && s.shortcut !== store.get('shortcut')) {
    store.set('shortcut', s.shortcut);
    registerShortcut();
    refreshTrayMenu();
  }
  return { success: true };
});

// Tabs ("modes") in the Help me picker are fully user-owned: renamable,
// addable, deletable, reorderable. DEFAULT_MODES only seeds a fresh install —
// existing installs (which predate user-owned tabs) get seeded with it once
// too, and normalizeCategory's case-insensitive fallback quietly upgrades any
// already-stored lowercase 'reply'/'write'/'understand' categories to match
// the very next time presets are normalized, so there's no separate one-time
// migration step to run or get wrong.
function getModes() {
  let modes = store.get('toneModes');
  if (!Array.isArray(modes) || modes.length === 0) {
    modes = DEFAULT_MODES.slice();
    store.set('toneModes', modes);
  }
  return modes;
}

ipcMain.handle('get-presets', () => {
  // normalizePresets both fills in category/blurb/isDefault for presets saved
  // by an older version of the app (which had none of those fields) and
  // fixes up the "exactly one default per category" invariant — cheap enough
  // to run on every read rather than a one-time migration flag.
  const presets = normalizePresets(store.get('presets', DEFAULT_PRESETS), getModes());
  store.set('presets', presets);
  return presets;
});

ipcMain.handle('get-tone-modes', () => getModes());

// Which tabs show the free-form "additional context" line instead of a plain
// Send button — a UX property of the tab, not of any one preset in it (both
// Email and Message, under Reply, want it). Persisted by name so a rename
// carries it along and a delete drops it, rather than resetting to nothing
// the moment "Reply" gets renamed to something else.
function getIntentModes() {
  let modes = store.get('intentModes');
  if (!Array.isArray(modes)) {
    modes = getModes().includes('Reply') ? ['Reply'] : [];
    store.set('intentModes', modes);
  }
  return modes;
}

ipcMain.handle('get-intent-modes', () => getIntentModes());

// The Settings window edits presets while the popup sits hidden behind it
// (or isn't open at all) — without this, the popup's already-loaded page
// only picks up preset changes on its next full reload, which in practice
// meant quitting and relaunching the app just to see a reordered list.
function broadcastPresetsUpdate(presets) {
  if (mainWindow) mainWindow.webContents.send('presets-updated', presets);
}

function broadcastModesUpdate(modes) {
  if (mainWindow) mainWindow.webContents.send('modes-updated', modes);
}

ipcMain.handle('save-preset', (e, { label, prompt, category, icon, blurb, tone, isEmail, isDefault }) => {
  if (!validateLabel(label)) return { success: false, error: 'Please enter a preset name' };
  const presets = upsertPreset(store.get('presets', DEFAULT_PRESETS), { label, prompt, category, icon, blurb, tone, isEmail, isDefault }, getModes());
  store.set('presets', presets);
  broadcastPresetsUpdate(presets);
  return { success: true, presets };
});

ipcMain.handle('delete-preset', (e, label) => {
  const presets = deletePreset(store.get('presets', DEFAULT_PRESETS), label, getModes());
  store.set('presets', presets);
  broadcastPresetsUpdate(presets);
  return { success: true, presets };
});

ipcMain.handle('reorder-presets', (e, incoming) => {
  const presets = applyPresetEdits(store.get('presets', DEFAULT_PRESETS), incoming, getModes());
  store.set('presets', presets);
  broadcastPresetsUpdate(presets);
  return { success: true, presets };
});

ipcMain.handle('add-tone-mode', () => {
  const modes = addMode(getModes());
  store.set('toneModes', modes);
  broadcastModesUpdate(modes);
  return { success: true, modes };
});

ipcMain.handle('rename-tone-mode', (e, { from, to }) => {
  const result = renameMode(getModes(), store.get('presets', DEFAULT_PRESETS), from, to);
  if (!result) return { success: false, error: 'Enter a unique tab name' };
  store.set('toneModes', result.modes);
  store.set('presets', result.presets);
  const renamedTo = to.trim();
  store.set('intentModes', getIntentModes().map((m) => (m === from ? renamedTo : m)));
  broadcastModesUpdate(result.modes);
  broadcastPresetsUpdate(result.presets);
  return { success: true, modes: result.modes, presets: result.presets };
});

ipcMain.handle('delete-tone-mode', (e, name) => {
  const result = deleteMode(getModes(), store.get('presets', DEFAULT_PRESETS), name);
  if (!result) return { success: false, error: 'Cannot delete the last tab' };
  store.set('toneModes', result.modes);
  store.set('presets', result.presets);
  store.set('intentModes', getIntentModes().filter((m) => m !== name));
  broadcastModesUpdate(result.modes);
  broadcastPresetsUpdate(result.presets);
  return { success: true, modes: result.modes, presets: result.presets };
});

ipcMain.handle('reorder-tone-modes', (e, orderedNames) => {
  const modes = reorderModes(getModes(), orderedNames);
  store.set('toneModes', modes);
  broadcastModesUpdate(modes);
  return { success: true, modes };
});

ipcMain.handle('claude-request', async (e, { text, prompt, isEmail, presetLabel }) => {
  const apiKey = store.get('apiKey', '');
  const model = store.get('model', DEFAULT_MODEL);
  const effort = store.get('effort', DEFAULT_EFFORT);
  const workspaceId = store.get('workspaceId', '');
  if (!apiKey) return { success: false, error: 'API key not set. Open Settings from the menu bar icon.' };

  const { system, content } = buildClaudeRequest(text, prompt, isEmail);
  const body = { model, max_tokens: 1024, system, messages: [{ role: 'user', content }] };
  // Sonnet 5, Opus 5, and Fable 5 default to adaptive thinking with no
  // `thinking` param needed — effort just tunes how much of it they do.
  // Haiku 4.5 is an older-tier model that rejects the param outright.
  if (!EFFORT_UNSUPPORTED_MODELS.includes(model)) body.output_config = { effort };

  // Identity-linked API keys (issued to a specific user within an org, as
  // opposed to a standalone workspace key) require this header naming which
  // workspace the request acts in, or the API rejects every call.
  const headers = {
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01'
  };
  if (workspaceId) headers['anthropic-workspace-id'] = workspaceId;

  try {
    // Electron's net.fetch (Chromium's network stack) instead of Node's
    // built-in fetch: Node's fetch only trusts its own bundled CA list and
    // fails with SELF_SIGNED_CERT_IN_CHAIN on networks with a TLS-inspecting
    // corporate proxy, since it never consults the OS/system trust store the
    // way curl, Safari, and Chrome do. net.fetch does.
    const res = await net.fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers,
      body: JSON.stringify(body)
    });
    const data = await res.json();
    if (!res.ok) throw new Error((data.error && data.error.message) || ('API Error: ' + res.status));
    const textBlock = Array.isArray(data.content)
      ? data.content.find((b) => b.type === 'text' && b.text)
      : null;
    const out = textBlock ? textBlock.text : '';
    if (!out) throw new Error('No text in response: ' + JSON.stringify(data).slice(0, 300));
    if (presetLabel) {
      const presets = incrementUses(store.get('presets', DEFAULT_PRESETS), presetLabel);
      store.set('presets', presets);
      broadcastPresetsUpdate(presets);
    }
    return { success: true, data: out, isEmail };
  } catch (err) {
    // fetch() wraps every network-level failure (DNS, TLS, proxy block,
    // timeout, connection reset) in the same generic "fetch failed" message
    // and puts the real reason in err.cause — surface both, and log the full
    // error to the terminal, or a corporate-proxy/DNS/TLS issue is
    // indistinguishable from a typo in the API key.
    console.error('claude-request failed:', err);
    const detail = err.cause ? (err.cause.code || err.cause.message || String(err.cause)) : null;
    return { success: false, error: detail ? `${err.message} (${detail})` : err.message };
  }
});

ipcMain.on('hide-window', () => mainWindow && mainWindow.hide());
ipcMain.on('minimize-window', (e) => {
  const win = BrowserWindow.fromWebContents(e.sender);
  if (win) win.minimize();
});
ipcMain.on('toggle-maximize-window', (e) => {
  const win = BrowserWindow.fromWebContents(e.sender);
  if (!win) return;
  if (win.isMaximized()) win.unmaximize(); else win.maximize();
});
ipcMain.on('open-settings', () => openSettingsWindow());
ipcMain.on('close-settings', () => settingsWindow && settingsWindow.close());
ipcMain.on('open-accessibility-settings', () => shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'));
ipcMain.on('open-automation-settings', () => shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Automation'));

ipcMain.handle('check-permissions', async () => ({
  accessibility: checkAccessibilityGranted(),
  automation: await checkAutomationGranted()
}));
ipcMain.on('copy-to-clipboard', (e, t) => clipboard.writeText(t));

// Opens the user's own default mail client with a pre-filled draft rather
// than sending anything ourselves — a desktop app has no backend to send
// mail through, and this way the user reviews and hits Send themselves in
// their own mail app, using their own account.
ipcMain.handle('send-feedback', (e, body) => {
  const subject = encodeURIComponent('Per My Last Feedback');
  const encodedBody = encodeURIComponent(body || '');
  shell.openExternal(`mailto:${FEEDBACK_EMAIL}?subject=${subject}&body=${encodedBody}`);
  return { success: true };
});

// There's no update server or auto-updater wired up yet — this tells the
// user that plainly instead of a spinner that implies a real check happened.
ipcMain.handle('check-for-updates', () => {
  dialog.showMessageBox({
    type: 'info',
    title: 'Check for Updates',
    message: `You're on version ${app.getVersion()}`,
    detail: "Automatic update checking isn't set up yet — for now, download new builds from wherever you got this one."
  });
  return { success: true };
});

// The shortcut recorder needs the *currently active* global hotkey out of the
// way while it's listening for a new combo — otherwise re-recording the
// exact same combo that's still registered gets intercepted by the OS-level
// globalShortcut binding before it ever reaches the Settings window's own
// keydown handler, and nothing appears to happen. Resuming re-registers
// whatever's actually saved in the store, ignoring any unsaved edits still
// sitting in the recorder — nothing is meant to take effect until Save.
ipcMain.on('suspend-shortcut-recording', () => globalShortcut.unregisterAll());
ipcMain.on('resume-shortcut-recording', () => registerShortcut());
ipcMain.handle('get-app-name', () => app.getName());
ipcMain.handle('get-app-version', () => app.getVersion());

// Settings' Save button always writes whatever is in the shortcut field, so
// anyone who saved settings before this fix now has the old, collision-prone
// default pinned in the store even though they never intentionally chose it.
// Move them onto the new default the same way a fresh install gets it.
if (store.get('shortcut') === LEGACY_DEFAULT_SHORTCUT) {
  store.set('shortcut', DEFAULT_SHORTCUT);
}

// Pre-dates the US/UK English split — anyone who saved settings back then has
// the old plain 'en' pinned in the store, which no longer matches any option
// in the App Language dropdown.
if (store.get('appLanguage') === 'en') {
  store.set('appLanguage', 'en-US');
}

// Anthropic's current model table uses the bare id — anyone who saved
// settings while the Haiku option still carried a dated snapshot suffix has
// that pinned in the store.
if (store.get('model') === 'claude-haiku-4-5-20251001') {
  store.set('model', 'claude-haiku-4-5');
}

app.whenReady().then(() => {
  isEnabled = store.get('isEnabled', true);
  createMainWindow();
  createTray();
  registerShortcut();
  if (app.dock) {
    app.dock.setIcon(nativeImage.createFromPath(path.join(__dirname, 'assets', 'dock-icon.png')));
    if (!store.get('showInDock', true)) app.dock.hide();
  }
  // Launching the app directly (Finder, Spotlight, Dock icon while not
  // already running) should actually show something — otherwise it looks
  // like nothing happened beyond an icon appearing in the Dock/menu bar.
  // First-time setup (no API key yet) still takes priority and opens
  // Settings instead, same as before.
  if (!store.get('apiKey')) openSettingsWindow();
  else showMainWindow();
});

// mainWindow.on('close') only lets the window actually close when
// app.isQuitting is true — otherwise it hides instead, so the app keeps
// running in the menu bar. That flag was only ever set by our own tray
// "Quit" item, so a quit initiated any other way (Dock → Quit, Cmd+Q) never
// set it, and close's preventDefault() silently blocked the quit. before-quit
// fires for every quit path, so setting it here covers all of them.
app.on('before-quit', () => { app.isQuitting = true; });

// Electron doesn't auto-show a hidden window when a running app's Dock icon
// is clicked (unlike native Mac apps) — 'activate' is the event for that,
// and it only fires when the Dock icon is actually visible (Show in Dock on).
app.on('activate', () => showMainWindow());

app.on('will-quit', () => globalShortcut.unregisterAll());
app.on('window-all-closed', (e) => {});
