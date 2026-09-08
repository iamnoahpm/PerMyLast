# Handoff: Per My Last — Main window + Settings

## Overview
Per My Last is a macOS menu-bar/desktop utility. The user selects text anywhere, presses a global hotkey (⇧⌘W), and the app drafts a reply / rewrite / explanation using Claude with the user's own API key.

This handoff covers two screens:
1. **Main App** — capture → pick a tone preset → optional intent → generated draft. Includes inline prompt editing that overwrites the corresponding preset in Settings.
2. **Settings** — one window, four tabs: General, Tone Presets, Permissions, Advanced.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes that show the intended look and behavior. They are **not production code to copy**. The task is to **recreate these designs in the target codebase's existing environment** (SwiftUI, Electron + React, Tauri, etc.) using its established patterns, component library, and state management. If no environment exists yet, choose the framework that best fits a macOS desktop utility and implement the designs there.

The HTML uses a small in-house template runtime (`support.js`, `<x-dc>`, `{{ holes }}`, `<sc-for>`, `<sc-if>`). Ignore that runtime — read the markup for structure/styling and the `class Component` block for state and behavior.

## Fidelity
**High-fidelity.** Colors, type, spacing, radii, copy and interaction states are final and should be matched closely. Numbers below are exact.

Two things are intentionally *not* final:
- Emoji are placeholders for real icons (SF Symbols or the app's icon set).
- Data is mock (API key, usage counts, permission states, draft output text).

---

## Design Tokens

### Colors
| Role | Hex |
|---|---|
| Accent / primary action | `#2b6cf6` |
| Ink (primary text) | `#17171a` |
| Titlebar / dark button | `#1b1b1d` |
| Body text secondary | `#4a4a52` |
| Body text tertiary | `#6b6b73` |
| Label muted | `#7a7a82` |
| Label subtle | `#8a8a92` |
| Placeholder / hint | `#9a9aa2`, `#a0a0a8` |
| Disabled / faint | `#b0b0b8`, `#b6b6be`, `#c3c3cb` |
| Border strong | `#dedee3` (inputs), `#e0e0e5` (buttons) |
| Border default | `#e4e4e9` |
| Divider | `#ececf0`, `#f0f0f3` |
| Surface page (settings body) | `#f7f7f9` |
| Surface card | `#ffffff` |
| Surface inset | `#f2f2f5`, `#f6f6f8`, `#fafafb` |
| Desktop backdrop | `#e9e9ec` |
| Success bg / text | `#e7f4ed` / `#0f6b48`; banner `#f2faf6` / border `#cfe8dc` / dot `#127a52` |
| Warning bg / text | `#fbeed3` / `#8a6205`; banner `#fdf8ec` / border `#f0dfb4` / dot `#b8860b` |
| Danger text / bg | `#b3261e` / `#fdf3f2`, border `#e6dcdc` |
| Edited pill (main app) | bg `#fff4e0`, text `#8a5a00` |
| Wartime active chip | `#fbe2a7`; note bg `#fdf8ec`, rule `#e5b94e` |
| Peacetime active chip | `#dbe6ff`; note bg `#f0f5ff`, rule `#8fb0ff` |
| macOS traffic lights | `#ff5f57`, `#febc2e`, `#28c840` |

Accent is a themeable prop; alternates used in review: `#17171a`, `#0f7b6c`, `#7c3aed`.

### Typography
- UI font: **Plus Jakarta Sans** (400/500/600/700), fallback `-apple-system`.
- Mono font: **JetBrains Mono** (400/500) — API key, model id, workspace id, export textarea.
- Scale: 17px/700 page title · 15px/700 tab label (presets) · 14px/700 card title · 14px/500-700 main tabs · 13.5px input & row label · 13px select/option · 12.5px body & buttons · 12px meta · 11.5px hint · 11px/700 uppercase section label (`letter-spacing: .07em`) · 10.5px/700 uppercase pill (`.04em`).
- Line-height 1.5–1.6 on prose; titles default.

### Spacing / shape
- Radii: `12px` window, `10px` card/section, `9px` inset & main-app input, `8px` input/select/tab-top, `7px` small button, `6px` segmented item, `5px` pill, `999px` chip/toggle.
- Common paddings: card row `13px 14px`; section body `18–20px 20–22px`; window content `14px 16px 16px`.
- Gaps: `18px` between settings sections, `10px` between cards, `12px`/`14px` inside rows, `8px` between controls.
- Shadows: window `0 24px 60px rgba(0,0,0,.28)`; card rest `0 1px 2px rgba(0,0,0,.03)`; card expanded `0 6px 18px rgba(0,0,0,.07)`; segmented knob `0 1px 2px rgba(0,0,0,.12)`; toggle knob `0 1px 2px rgba(0,0,0,.25)`.
- Focus: all inputs `outline: none; border-color: #2b6cf6`.
- Transitions: `.15s` (carets, toggles), `.3s` (Saved fade), `.7s` (re-check spin).

### Window frame (both screens)
720px wide, centered, radius 12, dark titlebar 38px tall (`#1b1b1d`) with 11px traffic lights (7px gap) and centered 13px/600 white title. Main App height 660px; Settings 720px. Titlebar holds **no app controls** (see Change note below).

### Footer (both screens)
34px tall, `border-top: 1px solid #e5e5e8`, white, 11.5px `#9a9aa2`: `Version 1.4.2 | Send feedback | Check for updates`. Separators are 1×11px `#dcdce1`. On Settings only, right-aligned: “Changes save as you make them”.

---

## Screen 1 — Main App (`Main App.dc.html`)

**Purpose:** capture text, choose how to handle it, get a draft.

### Layout (top → bottom, 14/16/16 padding, 12px gap, all inside a flex column)
1. **Tab strip** — bottom border `#ececf0`. Left: horizontally scrollable tab buttons (`Reply`, `Write`, `Understand`) padded `6px 10px 9px`, 14px, active 700 `#17171a` with `inset 0 -2px 0 accent`, inactive 500 `#8a8a92`. Right, flush to the border: **⚙ Settings** button — 28px tall, `padding 0 10px`, radius 7, border `#e6e6eb`, white, 12px/600 `#6a6a72`, `margin-bottom: 5px`; hover bg `#f4f4f6`, text `#17171a`, border `#dcdce1`.
2. **Source textarea** — 3 rows, full width, padding `11px 12px`, border `#dedee3`, radius 9, 13.5px, line-height 1.55, `resize: none`. Placeholder: `Select text anywhere, then press ⇧⌘W — or paste here`. Word count sits absolutely at `right 10px / bottom 8px`, 11px `#b0b0b8`, shown only when there is text (`"N words"`).
3. **Preset chips** — wrapping flex row, 8px gap. Chip: `padding 7px 12px`, radius 999, `1.5px` border, 12.5px. Active: border `#17171a`, bg `#f4f4f6`. Inactive: border `#e4e4e9`, bg `#fff`. Contents: icon (13px) · name (700) · summary (left border `1px #dcdce1`, `padding-left: 7px`, `#7a7a82` active / `#9a9aa2` inactive).
4. **Prompt meta row** — 12px `#7a7a82`, 10px gap: disclosure button `› Prompt` (caret rotates 90° when open, 12px/600, hover `#17171a`) · 1×12px divider `#e2e2e6` · `Tone <strong>{tone}</strong>` · then, conditionally, the **Edited** pill (18px tall, radius 999, `#fff4e0`/`#8a5a00`, 10.5px/700 uppercase) and/or a transient `Saved to {Tab} › {Preset}` in 12px/600 `#0f7b6c`.
5. **Prompt panel** — see *Prompt editing* below.
6. **Intent row** — 8px gap. Intent input (40px tall, radius 9, border `#dedee3`, 13.5px) renders **only for tabs in `INTENT_TABS`** (currently `["Reply"]`). Send button: 40px tall, `padding 0 18px`, radius 9, accent bg, white 13.5px/700, label `Send` (or `Send again` after a run) plus `⌘↵` at 12px/`opacity .6`. Send is `flex-shrink: 0` when the intent input is present, otherwise `flex: 1` (full-width).
7. **Output panel** — `flex: 1`, radius 10, overflow hidden. Empty: bg `#fafafb`, border `#ececed`, centered 12.5px `#a0a0a8` — “Your draft appears here.” + hint (`Pick a preset above, add your intent if you want, then press ⌘↵.` on intent tabs, otherwise `Pick a preset above, then press ⌘↵.`). Filled: bg `#fff`, border `#e4e4e9`, with a 9px/12px header row (`border-bottom #ececf0`) holding `{Preset} · {Tone}` in 11px/700 uppercase `#8a8a92`, then **Regenerate** (white, border `#e0e0e5`) and **Copy** (`#1b1b1d`, white text), both 26px tall. Body scrolls, `padding 12px`, 13.5px, line-height 1.6, `white-space: pre-wrap`.

### Prompt editing (new behavior — implement carefully)
- Collapsed by default. `› Prompt` toggles `promptOpen`; collapsing also exits edit mode.
- **Read state** (open, not editing): inset panel `padding 10px 12px`, radius 9, bg `#f6f6f8`, border `#ececed`, 12.5px `#4a4a52`, `cursor: text`; hover border `#d6d6dd`, bg `#f2f2f5`. A `Click to edit` affordance sits at `right 10px / bottom 8px`, 10.5px/600 `#a0a0a8`. **Both single click and double click enter edit mode** (`onClick` and `onDoubleClick` → same handler).
- **Edit state**: container radius 9, border `1.5px #2b6cf6`, white. Textarea 4 rows, borderless, `padding 10px 12px`, 12.5px/1.55, `resize: none`. Action bar below: `border-top #f0f0f3`, bg `#fafafb`, `padding 8px 10px` — left: `Saves to <strong>{Tab} › {Preset}</strong> in Settings` (11.5px `#9a9aa2`); right: `Reset to original` (text button, only when an override exists), `Cancel` (white, border `#e0e0e5`), `Save & overwrite` (accent, white, 700). All 27px tall.
- **Keyboard**: `Esc` cancels; `⌘↵`/`Ctrl+↵` saves.
- **Save semantics**: trim the draft. If empty **or identical to the preset's original prompt**, delete the override (back to original). Otherwise store it keyed by preset id. This write is the same store Settings → Tone Presets edits — i.e. saving here **overwrites the corresponding preset's prompt in Settings**.
- After save: exit edit mode, show `Saved to {Tab} › {Preset}` for **2600ms** (clear any pending timer first). The `Edited` pill persists as long as an override exists.
- Switching tab resets preset selection to the tab's first preset, clears intent, exits edit mode and clears the flash.

### Main App state
```
tab: string                  // active tab, default "Reply"
presetId: string             // active preset, default first of tab
promptOpen: bool             // prompt disclosure
source: string               // captured/pasted text
intent: string               // optional instruction
sent: bool                   // has a draft been generated
overrides: { [presetId]: string }  // edited prompts → persist; same store as Settings presets
editing: bool                // prompt edit mode
draft: string                // in-progress prompt text
savedFlash: bool             // 2.6s confirmation
```
Derived: `prompt = overrides[presetId] ?? preset.prompt`; `isEdited = !!overrides[presetId]`; `hasIntent = INTENT_TABS.includes(tab)`; `charCount` = word count of `source`.

Editing `source` sets `sent: false` (invalidates the old draft). Choosing a preset also sets `sent: false`.

### Content (mock, safe to reuse)
Tabs and presets: **Reply** — 📧 Email “Workplace email reply” (Direct), 💬 Message “Short chat / DM” (Warm). **Write** — ✍️ Rewrite like Native (Neutral), 🧑 Rewrite Like Me (Personal), 🧓 Fix Grammar (Neutral), 👔 Professional (Formal). **Understand** — 🔍 What are they asking? (Plain), 🧭 Read between the lines (Analytical). Full prompt strings and sample outputs are in the file's `TABS` constant.

---

## Screen 2 — Settings (`Settings.dc.html`)

One window, tab bar under the titlebar: `display: flex; gap: 2px; padding: 8px 12px 0; border-bottom: 1px solid #e5e5e8`. Each tab is a vertical icon+label button, `padding 7px 14px 8px`, radius `8px 8px 0 0`, icon 15px, label 12px/600; active color = accent with `inset 0 -2px 0 accent`; hover bg `#f4f4f6`. Content area scrolls on `#f7f7f9`.

Tabs: **General** (☀), **Tone Presets** (▤), **Permissions** (🛡), **Advanced** (✎). When a required permission is missing, the Permissions tab label gets a ` •` suffix and color `#b8860b`.

**Save model:** everything applies immediately. A `Saved` label (11px/600 `#8ee0b0`) fades in at the right of the titlebar for 2s after any change (`touch()` helper sets `savedAt`). Structural preset edits (add/delete/reorder) intentionally do not flash.

### Shared row pattern
Card = radius 10, border `#e4e4e9`, white, `overflow: hidden`; rows `display: flex; align-items: center; gap: 14px; padding: 13px 14px`, separated by a 1px `#f0f0f3` line. Left column fixed **176px**: title 13.5px/600 `#17171a` + hint 11.5px `#9a9aa2`. Right side `flex: 1`.

Standard controls:
- **Toggle**: 40×23 track, radius 999, `padding 2px`, bg accent when on else `#d8d8de`; knob 19px white circle, shadow `0 1px 2px rgba(0,0,0,.25)`; justify start/end.
- **Segmented**: wrapper `display: flex; gap: 3px; padding: 3px; background: #f2f2f5; border-radius: 8px`; item `flex: 1`, 28px tall, radius 6, 12px; active = white bg, 700, shadow `0 1px 2px rgba(0,0,0,.12)`; inactive `#7a7a82`.
- **Select / input**: 34px tall (32px in dense spots), radius 8, border `#dedee3`, 13px.
- **Disclosure**: text button `› Label`, caret rotates 90°, 12.5px/600 `#7a7a82` → hover `#17171a`.

### General
Sections: **Claude connection**, **Behaviour**, **Language** (11px/700 uppercase `#8a8a92` label, `margin 0 2px 8px`).

1. **API key** — status pill (`✓ Verified` green / `Missing` amber) + masked key `••••••••••••••••••` + last 4 in mono 12.5px; button `Replace` / `Add key` / `Editing…`. Editing expands a row indented to 174px: mono input (placeholder `sk-ant-api03-…`), `Verify & save` (dark) + `Cancel`, plus hint linking to console.anthropic.com and “stored in your macOS Keychain”.
2. **Model** — hint slot shows the raw model id in mono 11px; select of `claude-sonnet-5` (recommended), `claude-opus-4-6` (most capable), `claude-haiku-4-5` (fastest).
3. **Effort** — 5-item segmented `Low / Medium / High / Extra / Max`; the left-column hint shows the selected item's explanation (e.g. High → “More thorough — a few seconds longer”).
4. **Workspace ID** — behind a disclosure with the inline rationale “only if you hit an ‘anthropic-workspace-id is required’ error”; reveals a 280px mono input (`wrkspc_…`) + explanation.
5. **Global shortcut** — current combo in a 30px pill (border `#e0e0e5`, bg `#f8f8fa`, 13px/600) with an ✕ clear button; `Change` button enters recording (`Press keys…`, accent bg) and resolves after 1.4s.
6. **Show in Dock** (hint “Off = menu bar only”) and **Launch at login** — toggles.
7. **My language** (target for Translate) and **App language** (English (US) / Tiếng Việt) selects; `Help translate` link beside the latter.

### Tone Presets
Header: 17px/700 “Tone Presets” + 12.5px `#6b6b73` description (max-width 560px).

**Tab strip (user-owned):** each tab is a draggable div, `padding 7px 10px 9px`, radius `8px 8px 0 0`, 15px, active white bg + 700 + `inset 0 -2px 0 accent`. Contents: grip `⠿` (visible only on the active tab, `cursor: grab`) · label · count badge (min 19px, radius 10, 11px/700; accent bg + white when active, else `#e8e8ec`/`#8a8a92`) · on the active tab only, ✎ rename and ✕ delete (20px, hover bg `#eaeaef`; delete hover `#fdf0ef`/`#b3261e`, disabled at 30% when only one tab remains). `+ New tab` button after the strip: dashed border `#cfcfd6`, radius 7.
- Rename: click ✎ or double-click the label → inline 96px input, autofocus; Enter commits, Esc cancels, blur commits (guarded by a 350ms grace so the opening click doesn't immediately blur). Empty or duplicate name reverts.
- Add: creates `New tab` (`New tab 2`, 3…), selects it, opens rename immediately.
- Reorder: HTML5 drag; on `dragEnter` over another tab, splice the dragged tab before/after it depending on direction.
- Delete: removes the tab, its presets and its default; falls back to the first remaining tab.

**Caption row:** `N action(s) in {Tab} · drag to reorder`, 12px/600 uppercase `#8a8a92`, with a 1px `#e8e8ec` rule filling the rest.

**Preset cards** (10px gap): collapsed row = grip `⠿` · 30px icon tile (radius 8, bg `#f2f2f5`) · name 14px/700 + optional `Default` chip (`accent14` bg, accent text) · truncated summary 12.5px `#7a7a82` · ★/☆ set-default button (30px, accent when set) · `Edit`/`Close` button. Expanded (border `#d3d3da`, shadow `0 6px 18px rgba(0,0,0,.07)`) reveals, indented to 68px with a `#f0f0f3` top border: **Name** (flex 1) + **Subtitle shown on the chip** (flex 2) inputs; **Prompt** textarea (3 rows, `resize: vertical`); footer with `Tone {tone} · used {n} times` and `Delete` (danger outline) + `Done` (dark).
> The Prompt field here and the Main App's inline prompt editor must read and write the **same** preset record.

`+ Add to {Tab}` dashed 44px full-width button appends `✨ New preset / “Describe when to use this” / Neutral` and opens it expanded.

**Preview card** at the bottom (“Preview on the main screen”): mini tab row + the preset chips as they will appear in the main window (radius 999, `1.5px` border, dark border + `#f6f6f8` bg for the default preset).

### Permissions
1. **Status banner** — success (`#f2faf6` / border `#cfe8dc` / dot `#127a52`): “Hotkey capture is working” + “Press ⇧⌘W anywhere and your selection lands in Per My Last.” Warning (`#fdf8ec` / `#f0dfb4` / `#b8860b`): “Hotkey capture is off — N permission(s) missing” + which ones to grant, and the reassurance that everything else works without them. Warning state shows a dark CTA: `Open System Settings` (2+ missing) or `Open {Name}` (one).
2. **Permission cards** — 32px icon tile (bg tinted by state: granted `#eef8f3`, blocking `#fdf6e8`, else `#f2f2f5`), name 14px/700, state pill (`✓ Granted` / `Needed` / `Not granted`), `Optional` label for non-required ones, 12.5px `why` line, then `Without it: …` in 12px `#9a9aa2`. Blocking cards get border `#ecdcbc`. Right side: primary button (`Open Settings` — dark when blocking, grey when optional — or `Revoke` when granted) + `Show steps`/`Hide steps`. Steps panel: inset `#fafafb` card, uppercase label “How to grant it”, numbered 17px circles.
   - **Accessibility** (required): reads the highlighted text when the hotkey fires. Without it: paste by hand.
   - **Automation (System Events)** (required): triggers the copy step. Without it: silent capture failures in Mail and Slack.
   - **Notifications** (optional): ping when a long draft is ready.
3. **Re-check row** — `↻ Re-check` button (spins 360° over 700ms, resets the timer), `Checked Ns ago` / `Checked just now` (ticks every second), and a right-aligned `Reset demo state` link (prototype-only — drop it in production).
4. **Privacy card** — “What Per My Last does with this access”: reads only the current selection, no background reads, no keylogging, no screen recording; sent to Claude with the user's own key, not stored server-side; `Privacy details` link.

### Advanced
1. **Tools** card (“extra context Per My Last writes with”) — rows with icon tile, name, description, toggle:
   - ✍️ **Write My Way** — “Your level, tone, length, and format applied to every rewrite” (on).
   - ⭐ **VIP Contacts** — “Per-person tone rules for the people you write to most” — `Coming soon` pill, row at 60% opacity, toggle non-interactive at 50%.
   - ⚔️ **Wartime / Peacetime Mode** — “How much bluntness and urgency your company currently rewards” (on).
2. **Progressive disclosure:** each tool's settings section renders **only while its toggle is on**. With both off, show a dashed empty card: “No tools on / Turn one on above and its settings appear here.”
3. **Write My Way** section — **English level** toggle; when on, an inline test select (IELTS, TOEFL iBT, TOEIC, CEFR, Duolingo English Test), a 110px score input whose placeholder follows the test (`e.g. 7.5`, `e.g. 98`, `e.g. 850`, `e.g. B2`, `e.g. 120`), and the hint “Recent score or your best estimate”. Then **Default tone** select (Professional / Direct / Warm / Neutral / Casual), **Length** segmented (Short / Medium / Long / Custom, hint follows selection), **Format** select (Prose / Bullet points / Numbered list / Match the original). Footer note: audience and standing custom instructions are per-preset, coming soon.
4. **Wartime / Peacetime** section — section header carries a `Compare modes` / `Hide the other mode` toggle button (dark when on). Card: framing paragraph (“Your read on the company right now, not a universal standard…”), a 2-item segmented control with sublabels (`Wartime — Speed over sustainability` on `#fbe2a7`, `Peacetime — Sustainability over speed` on `#dbe6ff`), then a **2×2 grid** of trait groups (`#fafafb` cards): *Business environment*, *How work gets done*, *Culture and tone*, *How to operate well*. Each row: 11.5px `#8a8a92` label, the active mode's value in `#17171a`, and — when comparing — the other mode's value prefixed `Wartime:`/`Peacetime:` in `#b0b0b8`. Below, an italic note styled to the mode (bg + 3px left rule). Full trait copy is in the `TRAITS` constant.
5. **Export** — disclosure “Export this as context for another AI assistant” reveals a read-only mono textarea (7 rows) containing a generated brief: `COMPANY OPERATING MODE: {MODE}` + instruction paragraph + every trait group's active values + the mode note. `Copy` button (dark, flips to `Copied` for 1.5s) and the hint “Paste into ChatGPT, Claude, or a project brief.”

### Settings state
```
tab
// General
key, keyEditing, keyDraft, workspaceOpen, workspace,
model, effort, shortcut, recording, dock, launch, motherLang, appLang, savedAt
// Tone Presets
modes: string[]                     // user-owned tab order
mode: string                        // active tab
data: { [mode]: Preset[] }          // Preset = {id, icon, name, summary, tone, uses, prompt}
defaults: { [mode]: presetId|null }
expanded, editingTab, tabDraft, editStartedAt, dragTab
// Permissions
granted: { accessibility, automation, notifications }, permOpen, checkedAgo, spinning
// Advanced
writeOn, vipOn, modeOn, levelOn, test, score, tone, length, format,
opMode, compare, exportOpen, copied
```

---

## Change note vs. earlier drafts
- The gear icon was **removed from the titlebar**; Settings is now entered from the **⚙ Settings button at the right end of the Main App tab strip**. Keep OS chrome free of app controls.
- “Edit in Settings” link was **removed** from the prompt meta row — the prompt is edited inline instead.
- `General Settings.dc.html`, `Permissions Settings.dc.html`, `Tone Presets Settings.dc.html` are **superseded** by the single tabbed `Settings.dc.html`; they are not included in this bundle.

## Behaviour worth preserving
- Nothing is modal. No Save buttons except where a value must be validated (API key) or explicitly overwritten (prompt).
- Every destructive or unusual control states its consequence in place (`Without it: …`, “only if you hit … error”, “Saves to Reply › Email in Settings”).
- Timings: Saved flash 2000ms (Settings) / 2600ms (prompt save), copy confirmation 1500ms, shortcut recording 1400ms, re-check spin 700ms, rename blur grace 350ms.
- Empty states are informative, never decorative.

## Responsive behaviour
Fixed 720px window; no breakpoints. Only the tab strips scroll horizontally when they overflow. In a real macOS window, allow the window to grow: the source textarea and output panel should absorb extra height (output is the `flex: 1` region), and the preset chip row wraps.

## Assets
No image assets. Emoji stand in for icons throughout — replace with the app's icon set (SF Symbols suggested: `envelope`, `message`, `pencil`, `person`, `textformat.abc`, `briefcase`, `magnifyingglass`, `safari`, `gearshape`, `lock.open`, `bolt`, `bell`, `sparkles`, `star`, `shield`). Fonts are Google Fonts (Plus Jakarta Sans, JetBrains Mono) — bundle them or map to the codebase's equivalents.

## Files
| File | What it is |
|---|---|
| `Main App.dc.html` | Main window: capture, tabs, presets, inline prompt editing, output |
| `Settings.dc.html` | Settings window: General / Tone Presets / Permissions / Advanced |
| `support.js` | Prototype runtime only — **do not port**; needed just to open the HTML locally |

Open either HTML file directly in a browser to interact with the prototype.
