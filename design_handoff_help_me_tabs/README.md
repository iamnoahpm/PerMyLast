# Handoff: "Help me" tabbed action picker

## Overview
Redesign of the text-assist popover. Today the user pastes/captures text and picks
from a flat, unlabelled row of pills (Reply Email, Rewrite, Explain, Fix Grammar,
Professional). This redesign groups those actions by **intent** behind a single
segmented control labelled "Help me": **Reply / Write / Understand**. Selecting a
tab reveals only that tab's actions, each with a one-line description; selecting an
action shows the exact prompt that will be sent, then the user sends to Claude.

Goal: scannable at a glance, room to add actions without the window growing, and
the prompt is visible (read-only) instead of hidden behind deletable chips.

## About the Design Files
The files in this bundle are **design references created in HTML** — a prototype
showing intended look and behaviour, not production code to copy directly. The task
is to **recreate this design in the target codebase's existing environment** (React,
SwiftUI, Electron renderer, etc.) using its established patterns, component library
and styling approach. If no environment exists yet, pick the most appropriate
framework for the app and implement there.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii and interaction states below
are final and exact. Recreate pixel-for-pixel using the codebase's own primitives.

## Screens / Views

### 1. Assist popover (single view)
**Purpose:** Capture/confirm the source text, choose an intent + action, review the
prompt, send.

**Layout**
- Popover card: width `420px`, background `#FFFFFF`, border `1px solid #DCD9D3`,
  radius `14px`, shadow `0 18px 40px -24px rgba(20,19,18,0.45)`, `overflow:hidden`.
  Height is content-driven.
- Three stacked regions, top to bottom:
  1. **Input region** — padding `14px 14px 0`.
  2. **Chooser region** — padding `14px`, `display:flex; flex-direction:column; gap:12px`.
  3. **Prompt + send region** — padding `0 14px 14px`, `display:flex; flex-direction:column; gap:10px`.

**Components**

**a) Source text field** (textarea)
- `min-height:78px`, padding `11px 12px`, radius `9px`, background `#FFFFFF`.
- Border `1.5px solid #1F5EFF` with focus ring `box-shadow: 0 0 0 3px rgba(31,94,255,0.12)`
  (shown focused in the mock). Unfocused border: `1px solid #DCD9D3`, no ring.
- Text `14px / 1.5`, color `#141312`; placeholder color `#A5A29B`.
- Placeholder copy (verbatim):
  `Select text anywhere, then press ⌃⌘⇧S — or paste text here directly`
- Resizable vertically (as today).

**b) "Help me" label + tab bar** (row, `display:flex; align-items:center; gap:10px`)
- Label: text `Help me`, `11px`, weight `600`, `letter-spacing:0.08em`,
  `text-transform:uppercase`, color `#8A8781`, `white-space:nowrap`.
- Track: `flex:1`, `display:flex; gap:3px`, padding `3px`, background `#F2F0EC`, radius `9px`.
- Tab button: `flex:1`, padding `7px 10px`, radius `7px`, no border,
  font `13px / 600`, `cursor:pointer`, `transition: all .12s`.
  - Selected: background `#FFFFFF`, color `#141312`, shadow `0 1px 3px rgba(20,19,18,0.18)`.
  - Unselected: background `transparent`, color `#807C76`.
  - Hover (unselected): color `#141312`.
- Tabs, in order: `Reply`, `Write`, `Understand`.

**c) Action list** (`display:flex; flex-direction:column; gap:4px`)
- Row button: full width, `display:flex; align-items:center; justify-content:space-between; gap:12px`,
  padding `10px 11px`, radius `8px`, `text-align:left`, `cursor:pointer`, `transition: all .12s`.
  - Selected: background `#F7F5F2`, border `1px solid #141312`.
  - Unselected: background `transparent`, border `1px solid transparent`.
  - Hover (unselected): background `#F2F0EC`.
  - Always reserve the 1px border so rows don't shift on selection.
- Row title: `13px / 600`, color `#141312`.
- Row blurb: `12px`, line-height `1.4`, color `#807C76`.
- Trailing check `✓`: `13px / 700`, color `#141312`, `opacity: 1` when selected else `0`
  (kept in flow so width is stable).

**d) Prompt preview** (read-only)
- Border `1px solid #E2DFD9`, background `#FAF9F7`, radius `9px`, padding `10px 12px`,
  `display:flex; flex-direction:column; gap:5px`.
- Caption `PROMPT`: `10px / 600`, `letter-spacing:0.1em`, uppercase, color `#9A968F`.
- Body: `13px / 1.5`, color `#3D3A35`. Content = the selected action's prompt string.
- This replaces the old deletable chip row. If editing prompts must stay possible,
  make this a textarea in an "Edit prompt" affordance rather than editable by default.

**e) Send button**
- Full width, background `#141312`, color `#FFFFFF`, no border, radius `9px`,
  padding `12px`, font `14px / 600`, `cursor:pointer`.
- Hover: background `#2C2A26`. Active: `#000000`.
- Copy: `Send to Claude  ⌘↵` (two non-breaking spaces before the shortcut).
- Disabled state (no source text): background `#DCD9D3`, color `#8A8781`, `cursor:default`.

## Content model (tabs → actions → prompts)

| Tab | Action | Blurb | Prompt sent (prepended to source text) |
|---|---|---|---|
| Reply | Reply Email | Workplace email reply in your tone | You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a Direct tone. My reply intent: |
| Reply | Reply Message | Short chat / DM reply | Write a short, natural reply to this message. Keep it conversational and to the point. My reply intent: |
| Write | Rewrite | Clear, native English | Rewrite this text in clear, native English with a professional tone: |
| Write | Fix Grammar | Spelling and grammar only | Fix grammar and spelling: |
| Write | Professional | Raise the register | Make this more professional: |
| Understand | Explain | Plain-language summary | Explain this in simple terms: |
| Understand | Translate | Into your language from Settings | Translate this into my mother language (set in Settings): |

Translate resolves the target language from the app's Settings (existing
"mother language" preference); if unset, prompt the user in Settings before sending.

## Interactions & Behavior
- **Tab click** → sets active tab AND auto-selects that tab's **first** action, so the
  prompt preview is never empty. (Alternative if you prefer stickiness: remember the
  last action chosen per tab. Default in the prototype is first-action.)
- **Action click** → sets selection, updates prompt preview. Selection is single-choice
  across the whole popover (only one action can be active at a time).
- **Global hotkey** `Control+Command+Shift+S` → captures the current system selection
  into the source field and focuses the popover (unchanged from today).
- **⌘↵** → same as clicking Send, from anywhere in the popover.
- **Send** → concatenates `prompt + "\n\n" + sourceText` and dispatches to the model,
  same pipeline as today. Only the picker UI changes.
- **Transitions**: all state changes use `.12s` ease on background/border/color/shadow.
  No layout animation on tab switch — the list swaps instantly (the popover height
  changes between tabs; if that jump is objectionable, animate `height` at `.15s`
  or set a min-height equal to the tallest tab, 3 rows).
- **Keyboard**: tab bar is a roving-tabindex radiogroup (←/→ to move, Space to select);
  the action list is a listbox (↑/↓, Enter to select). `aria-selected` on both.
- **Loading**: while awaiting the model, Send shows a spinner + label `Sending…` and is
  disabled; the picker stays enabled.
- **Error**: inline message below the prompt box, `12px`, color `#B4291F`, with a Retry link.
- **Empty source text**: Send disabled; hovering shows tooltip "Select or paste text first".
- **Responsive**: fixed 420px popover — no responsive behaviour required.

## State Management
```
sourceText: string        // from hotkey capture or paste
activeTab: 'reply' | 'write' | 'understand'    // default 'reply'
selectedAction: string    // action id, default 'reply-email'
status: 'idle' | 'sending' | 'error'
settings.motherLanguage: string   // existing setting, read by Translate
```
Transitions: `activeTab` change → `selectedAction = firstActionOf(activeTab)`.
Derived: `prompt = ACTIONS[selectedAction].prompt`; `canSend = sourceText.trim() && status !== 'sending'`.
The tab/action catalogue is static data — keep it in one module so actions can be
added by editing data only, not markup.

## Design Tokens
**Colors**
- Ink / primary: `#141312`  · Button hover: `#2C2A26`
- Body text: `#3D3A35`  · Secondary text: `#807C76`  · Muted label: `#8A8781`  · Caption: `#9A968F`
- Placeholder: `#A5A29B`
- Surface: `#FFFFFF`  · Subtle surface: `#FAF9F7`  · Selected row: `#F7F5F2`  · Track / hover: `#F2F0EC`
- Border: `#DCD9D3`  · Border subtle: `#E2DFD9`
- Focus blue: `#1F5EFF`  · Focus ring: `rgba(31,94,255,0.12)`
- App backdrop: `#EFEEEC`  · Error: `#B4291F`

**Typography** — IBM Plex Sans (fallback `-apple-system, BlinkMacSystemFont, sans-serif`).
Substitute the codebase's UI font if one is established; keep the sizes/weights.
- 14/600 send button · 14/400 (1.5) textarea · 13/600 tab + action title · 13/400 (1.5) prompt body
- 12/400 (1.4) action blurb · 11/600 uppercase 0.08em "Help me" · 10/600 uppercase 0.1em "Prompt"

**Spacing** — 3, 4, 5, 7, 10, 11, 12, 14 px. Card padding 14px; region gap 12px; action gap 4px.

**Radius** — 7 (tab) · 8 (action row) · 9 (field, tab track, prompt box, send) · 14 (card).

**Shadows**
- Card: `0 18px 40px -24px rgba(20,19,18,0.45)`
- Selected tab: `0 1px 3px rgba(20,19,18,0.18)`
- Focus ring: `0 0 0 3px rgba(31,94,255,0.12)`

## Assets
None. The only glyphs are text characters: `✓` (selection tick), `⌃⌘⇧S` and `⌘↵`
(keyboard shortcuts). No icons or images required.

## Screenshots
`screenshots/` — rendered states of the final design:
- `01-tab.png` — Reply tab, Reply Email selected (default state)
- `02-tab.png` — Write tab, Rewrite selected (auto-selected first action)
- `03-tab.png` — Understand tab, Explain selected
- `04-tab.png` — Write tab, Professional selected (non-first action)

## Files
- `Help Me Tabbed.dc.html` — the final design (open directly in a browser; interactive:
  click tabs and actions to see selection + prompt behaviour).
- `support.js` — runtime needed by the HTML file; no need to port it.

Not included: the earlier exploration file `Grouped Actions.dc.html` (flat groups and
accordion variants), which lives in the design project if the alternatives are wanted.
