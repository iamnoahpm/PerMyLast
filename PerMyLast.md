An Electron menu bar app for macOS. Copy text anywhere with Cmd+C, press a global
hotkey (default Cmd+Shift+S), and a floating window appears with the clipboard text
loaded. Pick a prompt template or write your own, send it to the Claude API, and copy
the result back.

## Instructions for Claude Code
Create the file tree below at `/Users/macos/Library/Mobile Documents/com~apple~CloudDocs/05_Claude Projects/01_Claude Code/PerMyLast, writing each file with the exact contents given in this document. Then run `npm install`. Do not run
`npm start` yourself; the user will launch it.

## File tree

```
PerMyLast/
├── .gitignore
├── package.json
├── main.js
├── preload.js
└── renderer/
    ├── index.html
    └── settings.html
```

`node_modules/` and `dist/` are generated, not authored.

## Architecture

- **main.js** runs in Electron's main process. It owns the tray icon, the global
  shortcut, the two BrowserWindows, persisted settings (via `electron-store`), and
  all Claude API calls. API calls live here rather than in the renderer so the key
  never touches page context and no CORS header is needed.
- **preload.js** exposes a narrow `window.api` bridge. `contextIsolation` is on and
  `nodeIntegration` is off in both windows.
- **renderer/index.html** is the floating assistant window: frameless, transparent,
  always on top, draggable by its header.
- **renderer/settings.html** is a normal window for API key, model, and shortcut.

## Behaviour notes worth preserving

- The default prompt template is **Rewrite**, not Reply Email.
- `positionNearCursor()` clamps the window inside the current display's work area so
  a long result is never clipped off screen. This was a real bug earlier; keep it.
- The API response is read by scanning all content blocks for the first one of type
  `text`, rather than assuming `content[0]`. If no text is found it throws with the
  raw JSON. This prevents a silent blank result box.
- Reply Email mode is detected by the prompt containing "reply to this email" and
  swaps in an email-specific system prompt.
- `app.dock.hide()` makes this a menu bar only app with no Dock icon.

---

## .gitignore

```
node_modules/
dist/
.DS_Store
```

---

## package.json

```json
{
  "name": "permylast",
  "version": "1.1.0",
  "description": "Say what you mean, but professionally. Saving careers, one email, one message at a time",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "dist": "electron-builder --mac"
  },
  "devDependencies": {
    "electron": "^28.0.0",
    "electron-builder": "^24.9.1"
  },
  "dependencies": {
    "electron-store": "^8.1.0"
  },
  "build": {
    "appId": "com.claude.permylast",
    "productName": "Per My Last",
    "directories": { "output": "dist" },
    "mac": {
      "category": "public.app-category.productivity",
      "target": "dmg"
    }
  }
}
```

---

## main.js

```javascript
const { app, BrowserWindow, globalShortcut, ipcMain, Tray, Menu, clipboard, nativeImage, screen } = require('electron');
const Store = require('electron-store');
const path = require('path');

const store = new Store();
const DEFAULT_MODEL = 'claude-sonnet-5';
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
    alwaysOnTop: true,
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
}

function createSettingsWindow() {
  if (settingsWindow) { settingsWindow.focus(); return; }
  settingsWindow = new BrowserWindow({
    width: 620,
    height: 640,
    title: 'Claude Assistant Settings',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.js')
    }
  });
  settingsWindow.loadFile('renderer/settings.html');
  settingsWindow.on('closed', () => { settingsWindow = null; });
}

function showAssistant() {
  if (!isEnabled) return;

  const text = clipboard.readText();
  if (!text || !text.trim()) {
    mainWindow.webContents.send('no-text');
    positionNearCursor();
    mainWindow.show();
    return;
  }

  mainWindow.webContents.send('selected-text', text);
  positionNearCursor();
  mainWindow.show();
  mainWindow.focus();
}

function positionNearCursor() {
  const pt = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(pt);
  const b = display.workArea;
  const [w, h] = mainWindow.getSize();

  let x = pt.x + 10;
  let y = pt.y + 10;
  if (x + w > b.x + b.width)  x = b.x + b.width  - w - 10;
  if (y + h > b.y + b.height) y = b.y + b.height - h - 10;
  if (x < b.x) x = b.x + 10;
  if (y < b.y) y = b.y + 10;

  mainWindow.setPosition(Math.round(x), Math.round(y));
}

function createTray() {
  tray = new Tray(nativeImage.createEmpty());
  tray.setTitle('AI');
  refreshTrayMenu();
  tray.on('click', showAssistant);
}

function refreshTrayMenu() {
  const menu = Menu.buildFromTemplate([
    {
      label: isEnabled ? 'Enabled' : 'Disabled',
      click: () => {
        isEnabled = !isEnabled;
        store.set('isEnabled', isEnabled);
        refreshTrayMenu();
      }
    },
    { type: 'separator' },
    { label: 'Show Assistant', accelerator: store.get('shortcut', 'Command+Shift+S'), click: showAssistant },
    { label: 'Settings...', click: createSettingsWindow },
    { type: 'separator' },
    { label: 'Quit', accelerator: 'Command+Q', click: () => { app.isQuitting = true; app.quit(); } }
  ]);
  tray.setContextMenu(menu);
}

function registerShortcut() {
  globalShortcut.unregisterAll();
  const sc = store.get('shortcut', 'Command+Shift+S');
  globalShortcut.register(sc, showAssistant);
}

ipcMain.handle('get-settings', () => ({
  apiKey: store.get('apiKey', ''),
  model: store.get('model', DEFAULT_MODEL),
  shortcut: store.get('shortcut', 'Command+Shift+S')
}));

ipcMain.handle('save-settings', (e, s) => {
  if (s.apiKey !== undefined) store.set('apiKey', s.apiKey);
  if (s.model !== undefined) store.set('model', s.model);
  if (s.shortcut !== undefined && s.shortcut !== store.get('shortcut')) {
    store.set('shortcut', s.shortcut);
    registerShortcut();
    refreshTrayMenu();
  }
  return { success: true };
});

ipcMain.handle('claude-request', async (e, { text, prompt }) => {
  const apiKey = store.get('apiKey', '');
  const model = store.get('model', DEFAULT_MODEL);
  if (!apiKey) return { success: false, error: 'API key not set. Open Settings from the menu bar icon.' };

  const isEmail = prompt.toLowerCase().includes('reply to this email');
  let system, content;
  if (isEmail) {
    system = 'You are an email writing assistant. Write ONLY the reply email content, no preamble. Start with the greeting and end with a sign-off. Professional yet friendly unless told otherwise.';
    content = 'Email to reply to:\n' + text + '\n\nInstructions: ' + prompt.replace('Reply to this email.', '').replace('Additional context:', '').trim();
  } else {
    system = 'You are a text processing assistant. Respond ONLY with the processed result, no preamble, explanation, or surrounding quotation marks.';
    content = prompt + '\n\nText: ' + text;
  }

  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({ model, max_tokens: 1024, system, messages: [{ role: 'user', content }] })
    });
    const data = await res.json();
    if (!res.ok) throw new Error((data.error && data.error.message) || ('API Error: ' + res.status));
    const textBlock = Array.isArray(data.content)
      ? data.content.find((b) => b.type === 'text' && b.text)
      : null;
    const out = textBlock ? textBlock.text : '';
    if (!out) throw new Error('No text in response: ' + JSON.stringify(data).slice(0, 300));
    return { success: true, data: out, isEmail };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.on('hide-window', () => mainWindow && mainWindow.hide());
ipcMain.on('open-settings', () => createSettingsWindow());
ipcMain.on('copy-to-clipboard', (e, t) => clipboard.writeText(t));

app.whenReady().then(() => {
  isEnabled = store.get('isEnabled', true);
  createMainWindow();
  createTray();
  registerShortcut();
  if (app.dock) app.dock.hide();
  if (!store.get('apiKey')) createSettingsWindow();
});

app.on('will-quit', () => globalShortcut.unregisterAll());
app.on('window-all-closed', () => {});
```

---

## preload.js

```javascript
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  getSettings: () => ipcRenderer.invoke('get-settings'),
  saveSettings: (s) => ipcRenderer.invoke('save-settings', s),
  sendToClaude: (text, prompt) => ipcRenderer.invoke('claude-request', { text, prompt }),
  hideWindow: () => ipcRenderer.send('hide-window'),
  openSettings: () => ipcRenderer.send('open-settings'),
  copyToClipboard: (t) => ipcRenderer.send('copy-to-clipboard', t),
  onSelectedText: (cb) => ipcRenderer.on('selected-text', (e, t) => cb(t)),
  onNoText: (cb) => ipcRenderer.on('no-text', () => cb())
});
```

---

## renderer/index.html

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; background:transparent; overflow:hidden; }
  .window { background:#fff; border-radius:12px; box-shadow:0 20px 60px rgba(0,0,0,.3); margin:8px; height:calc(100vh - 16px); display:flex; flex-direction:column; overflow:hidden; }
  .header { background:linear-gradient(135deg,#667eea,#764ba2); color:#fff; padding:12px 16px; display:flex; justify-content:space-between; align-items:center; -webkit-app-region:drag; }
  .header .title { font-weight:600; font-size:14px; }
  .header .ctrls { display:flex; gap:8px; -webkit-app-region:no-drag; }
  .icon-btn { background:rgba(255,255,255,.2); border:none; color:#fff; width:28px; height:28px; border-radius:50%; cursor:pointer; font-size:16px; }
  .icon-btn:hover { background:rgba(255,255,255,.35); }
  .content { padding:16px; overflow-y:auto; flex:1; }
  .selected { background:#f5f5f5; border-left:3px solid #667eea; padding:10px; border-radius:6px; font-size:13px; color:#555; margin-bottom:12px; max-height:70px; overflow-y:auto; white-space:pre-wrap; user-select:text; }
  textarea { width:100%; padding:10px; border:2px solid #e0e0e0; border-radius:6px; font-size:13px; font-family:inherit; resize:vertical; min-height:60px; margin-bottom:10px; }
  textarea:focus { outline:none; border-color:#667eea; }
  .templates { display:flex; flex-wrap:wrap; gap:6px; margin-bottom:12px; }
  .tpl { background:#f0f0f0; border:1px solid #ddd; padding:5px 10px; border-radius:20px; font-size:11px; cursor:pointer; }
  .tpl:hover, .tpl.active { background:#667eea; color:#fff; border-color:#667eea; }
  .tpl.email { background:#e3f2fd; border-color:#2196F3; color:#1565C0; }
  .tpl.email:hover, .tpl.email.active { background:#2196F3; color:#fff; }
  .send { width:100%; background:linear-gradient(135deg,#667eea,#764ba2); color:#fff; border:none; padding:10px; border-radius:6px; font-size:14px; font-weight:600; cursor:pointer; }
  .send:disabled { opacity:.6; cursor:not-allowed; }
  #result { margin-top:14px; }
  .loading { text-align:center; color:#667eea; padding:16px; }
  .resp-text { background:#f9f9f9; border:1px solid #e0e0e0; border-radius:6px; padding:12px; font-size:14px; line-height:1.6; white-space:pre-wrap; user-select:text; max-height:220px; overflow-y:auto; margin-bottom:10px; }
  .actions { display:flex; gap:8px; justify-content:flex-end; }
  .act { border:none; color:#fff; padding:6px 14px; border-radius:6px; font-size:12px; font-weight:500; cursor:pointer; }
  .act.copy { background:#4caf50; }
  .err { background:#ffebee; color:#c62828; border-left:3px solid #f44336; padding:12px; border-radius:6px; font-size:13px; white-space:pre-wrap; }
</style>
</head>
<body>
  <div class="window">
    <div class="header">
      <span class="title">Claude Assistant</span>
      <div class="ctrls">
        <button class="icon-btn" id="settingsBtn" title="Settings">*</button>
        <button class="icon-btn" id="closeBtn" title="Close (Esc)">x</button>
      </div>
    </div>
    <div class="content">
      <div class="selected" id="selected">Copy text (Cmd+C), then press Cmd+Shift+S</div>
      <textarea id="prompt" rows="3"></textarea>
      <div class="templates">
        <button class="tpl active" data-t="Rewrite this text in clear, native English with a professional tone:">Rewrite</button>
        <button class="tpl" data-t="Summarize this in 2-3 sentences:">Summarize</button>
        <button class="tpl" data-t="Explain this in simple terms:">Explain</button>
        <button class="tpl" data-t="Fix grammar and spelling:">Fix Grammar</button>
        <button class="tpl" data-t="Make this more professional:">Professional</button>
        <button class="tpl email" data-t="Reply to this email. Additional context:">Reply Email</button>
      </div>
      <button class="send" id="send">Send to Claude (Cmd+Enter)</button>
      <div id="result"></div>
    </div>
  </div>

<script>
  const DEFAULT_PROMPT = 'Rewrite this text in clear, native English with a professional tone:';
  let currentText = '';
  let busy = false;

  const $ = (s) => document.querySelector(s);
  const promptEl = $('#prompt');
  const resultEl = $('#result');
  const sendBtn = $('#send');

  promptEl.value = DEFAULT_PROMPT;

  window.api.onSelectedText((t) => {
    currentText = t;
    $('#selected').textContent = t.length > 200 ? t.slice(0, 200) + '...' : t;
    resultEl.innerHTML = '';
    promptEl.focus();
  });

  window.api.onNoText(() => {
    currentText = '';
    $('#selected').textContent = 'No text on clipboard. Copy something (Cmd+C) and press Cmd+Shift+S again.';
    resultEl.innerHTML = '';
  });

  document.querySelectorAll('.tpl').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tpl').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      promptEl.value = btn.dataset.t;
      promptEl.focus();
    });
  });

  $('#closeBtn').addEventListener('click', () => window.api.hideWindow());
  $('#settingsBtn').addEventListener('click', () => window.api.openSettings());
  sendBtn.addEventListener('click', process);

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') window.api.hideWindow();
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') process();
  });

  async function process() {
    if (busy) return;
    const prompt = promptEl.value.trim();
    if (!prompt) { alert('Please enter a prompt'); return; }
    if (!currentText) { alert('No text. Copy something first (Cmd+C).'); return; }

    busy = true;
    sendBtn.disabled = true;
    sendBtn.textContent = 'Processing...';
    resultEl.innerHTML = '<div class="loading">Thinking...</div>';

    const r = await window.api.sendToClaude(currentText, prompt);

    if (r.success) {
      resultEl.innerHTML =
        '<div class="resp-text"></div>' +
        '<div class="actions"><button class="act copy">Copy</button></div>';
      resultEl.querySelector('.resp-text').textContent = r.data;
      resultEl.querySelector('.copy').addEventListener('click', () => {
        window.api.copyToClipboard(r.data);
        resultEl.querySelector('.copy').textContent = 'Copied';
        setTimeout(() => window.api.hideWindow(), 800);
      });
    } else {
      resultEl.innerHTML = '<div class="err"></div>';
      resultEl.querySelector('.err').textContent = 'Error: ' + r.error;
    }

    busy = false;
    sendBtn.disabled = false;
    sendBtn.textContent = 'Send to Claude (Cmd+Enter)';
  }
</script>
</body>
</html>
```

---

## renderer/settings.html

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; background:#f5f5f5; padding:24px; }
  h1 { color:#667eea; margin-bottom:20px; font-size:22px; }
  .card { background:#fff; border-radius:10px; padding:20px; margin-bottom:18px; box-shadow:0 2px 8px rgba(0,0,0,.08); }
  label { display:block; font-size:14px; font-weight:500; margin:10px 0 6px; }
  input, select { width:100%; padding:10px; border:2px solid #e0e0e0; border-radius:6px; font-size:14px; box-sizing:border-box; }
  input:focus, select:focus { outline:none; border-color:#667eea; }
  button { background:linear-gradient(135deg,#667eea,#764ba2); color:#fff; border:none; padding:12px 20px; border-radius:6px; font-size:15px; font-weight:600; cursor:pointer; width:100%; }
  .model-display { background:#e8f5e9; border-left:4px solid #28a745; padding:10px; border-radius:6px; margin-top:10px; }
  .model-display code { background:#fff; padding:2px 6px; border-radius:4px; color:#d63384; font-weight:600; }
  .custom { background:#fff3cd; border-left:4px solid #ffc107; padding:14px; border-radius:6px; margin-top:10px; }
  .custom small { color:#6c6c6c; font-style:italic; }
  .status { margin-top:14px; padding:12px; border-radius:6px; font-size:14px; display:none; }
  .status.ok { background:#e8f5e9; color:#2e7d32; display:block; }
  .status.err { background:#ffebee; color:#c62828; display:block; }
  a { color:#667eea; }
</style>
</head>
<body>
  <h1>Claude Assistant Settings</h1>

  <div class="card">
    <label for="apiKey">Claude API Key</label>
    <input type="password" id="apiKey" placeholder="sk-ant-api..." autocomplete="off">
    <small>Get one at <a href="https://console.anthropic.com/" target="_blank">console.anthropic.com</a></small>
  </div>

  <div class="card">
    <label for="model">Model</label>
    <select id="model">
      <option value="claude-sonnet-5">Claude Sonnet 5 (Recommended)</option>
      <option value="claude-opus-5">Claude Opus 5 (Most Capable)</option>
      <option value="claude-haiku-4-5-20251001">Claude Haiku 4.5 (Fastest)</option>
      <option value="claude-fable-5">Claude Fable 5 (Frontier)</option>
      <option value="other">Other (custom)</option>
    </select>
    <div class="model-display" id="modelDisplay"><strong>Selected model:</strong> <code id="modelValue"></code></div>
    <div class="custom" id="customWrap" style="display:none;">
      <label for="customModel">Custom model name</label>
      <input type="text" id="customModel" placeholder="e.g. claude-sonnet-5">
      <small>Enter the exact model string from Anthropic's docs.</small>
    </div>
  </div>

  <div class="card">
    <label for="shortcut">Global shortcut</label>
    <input type="text" id="shortcut" placeholder="Command+Shift+S">
    <small>Format: Command+Shift+S, Control+Alt+K, and so on.</small>
  </div>

  <button id="save">Save Settings</button>
  <div class="status" id="status"></div>

<script>
  const STD = ['claude-sonnet-5', 'claude-opus-5', 'claude-haiku-4-5-20251001', 'claude-fable-5'];
  const $ = (s) => document.querySelector(s);

  function refreshModelUI() {
    const sel = $('#model').value;
    if (sel === 'other') {
      $('#customWrap').style.display = 'block';
      $('#modelDisplay').style.display = 'none';
    } else {
      $('#customWrap').style.display = 'none';
      $('#modelDisplay').style.display = 'block';
      $('#modelValue').textContent = sel;
    }
  }

  function selectedModel() {
    return $('#model').value === 'other' ? $('#customModel').value.trim() : $('#model').value;
  }

  function status(msg, ok) {
    const s = $('#status');
    s.textContent = msg;
    s.className = 'status ' + (ok ? 'ok' : 'err');
  }

  $('#model').addEventListener('change', refreshModelUI);

  (async () => {
    const s = await window.api.getSettings();
    if (s.apiKey) $('#apiKey').value = s.apiKey;
    $('#shortcut').value = s.shortcut || 'Command+Shift+S';
    if (STD.includes(s.model)) {
      $('#model').value = s.model;
    } else {
      $('#model').value = 'other';
      $('#customModel').value = s.model;
    }
    refreshModelUI();
  })();

  $('#save').addEventListener('click', async () => {
    const apiKey = $('#apiKey').value.trim();
    const model = selectedModel();
    const shortcut = $('#shortcut').value.trim();
    if (!apiKey.startsWith('sk-ant-')) return status('API key must start with "sk-ant-"', false);
    if (!model) return status('Please choose or enter a model.', false);
    if (!shortcut) return status('Please enter a shortcut.', false);
    await window.api.saveSettings({ apiKey, model, shortcut });
    status('Saved. Using ' + model, true);
  });
</script>
</body>
</html>
```

---

## Setup

```bash
cd ~/Users/macos/Library/Mobile Documents/com~apple~CloudDocs/05_Claude Projects/01_Claude Code/PerMyLast
npm install
npm start
```

To build a distributable DMG:

```bash
npm run dist
open dist/
```

First launch is unsigned, so use right click then Open on the built app to get past
Gatekeeper.

## First run checklist

1. Settings opens automatically when no API key is stored. Paste a key from
   console.anthropic.com.
2. Confirm the model shows `claude-sonnet-5`, then click Save Settings even if
   nothing looks changed. See the stale settings note below for why this matters.
3. Select any text (no need to copy it first) and press Cmd+Shift+S. The first time,
   macOS will prompt to let Per My Last control "System Events" and to grant it
   Accessibility access — approve both, then press the hotkey again. Click Send to Claude.

## Known gotchas

**Stale settings survive a fresh checkout.** `electron-store` writes to
`~/Library/Application Support/claude-assistant/config.json`, keyed by app name, not
by project folder. An earlier version of this project stored a now retired model
string there, and a clean rebuild will still read it and fail with a model error.
Fix by saving the model again in Settings, or delete that config file to start fresh.

**Model strings are pinned snapshots and do get retired.** Requests to a retired
model ID return a 404. The four in the dropdown were current as of late August 2026.
The Other option exists so a new string can be dropped in without editing code.

**Do not reintroduce the browser access header.** The Chrome extension version of
this app needed `anthropic-dangerous-direct-browser-access`. Calls now run in the
Electron main process, so that header is unnecessary.

**Renderer console logs go to DevTools; main process logs go to the terminal.** When
debugging an API call, add the log in main.js and read the terminal running
`npm start`. DevTools for the frameless window is Cmd+Option+I.

**The hotkey needs two separate OS permissions, not one.** `showAssistant()` simulates
Cmd+C via `osascript`/System Events so the hotkey works on a plain text selection
without a manual copy first. macOS gates this behind both Automation permission (this
app controlling "System Events") and Accessibility permission — denying either makes
`simulateCopy()` fail silently from the app's point of view (osascript just exits
non-zero), which the UI surfaces as "Needs permission" rather than a clipboard result.
In dev mode (`npm start`) the permission prompts attach to Electron, not "Per My Last" —
check Electron's entries under System Settings → Privacy & Security if the packaged
app's own toggle doesn't appear.

## Possible next steps

- Add a Replace button that pastes the result back into the source app, which needs
  a synthetic Cmd+V (same Accessibility/Automation grant as the selection-read above).
- Persist a short history of prompts and results.
- Stream the response so long outputs appear progressively.
- Add user editable prompt templates instead of the six hardcoded ones.
```