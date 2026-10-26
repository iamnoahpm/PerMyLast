# Requirement: Animated empty-state illustrations for the four modes

**Product:** Per My Last (macOS app)
**Scope:** replace the current empty-state illustration (bubble mascot in sunglasses under an umbrella) with one animated beach illustration per mode.
**Assets in this folder:** `empty-reply.svg`, `empty-write.svg`, `empty-understand.svg`, `empty-ask.svg`

> **For Claude Code:** Implement the empty state of the output panel for each mode using the matching SVG in this folder. Keep the existing title and hint copy for each mode unless this file gives new copy. First check how the app renders UI (SwiftUI, AppKit, or a web view) and choose the implementation path in section 4 that fits. Report which path you used and why.

---

## 1. Mapping

| Mode | Asset | Scene | Why it fits |
|---|---|---|---|
| Reply | `empty-reply.svg` | One umbrella (same canopy width as Understand), two deckchairs close to the pole, facing the sea | Two people, one conversation |
| Write | `empty-write.svg` | One reclined lounger with a striped cushion (4 blue + 3 white lengthwise stripes on seat and backrest) angled toward the sea, umbrella planted behind it | Your own space to write |
| Understand | `empty-understand.svg` | An upright striped umbrella planted behind a full deckchair in 3/4 view, low seat, back reclined about 33°, flat icon style | Sit back, let it be explained |
| Ask | `empty-ask.svg` | An empty hammock between two leaning palm trunks at a soft sunset | Curious, open-ended, relaxed |

*The mapping is a proposal. To change it, swap the file names. No code changes are needed beyond that.*

## 2. Layout of the empty state (same for all modes)

- **Panel:** `surface-inset` background, 1px dashed `line-strong` outline, `radius-card`, padding 16 16 20. Content is centred.
- **Order, top to bottom:**
  1. **Illustration:** displayed at 200 × 110 pt, intrinsic size 240 × 132 at a 20:11 ratio, with 8pt below it.
  2. **Title:** 14pt, weight 700, `ink`.
  3. **Hint:** `body` style, `ink-muted`, with the shortcut in the `kbd` style.
- **Narrow windows:** below 380pt the illustration scales down proportionally, to no less than 160pt wide.

## 3. Copy per mode

| Mode | Title | Hint |
|---|---|---|
| Reply | Your draft appears here. | Paste their message, add your intent if you want, then press ⌘↵. |
| Write | [keep current] | [keep current] |
| Understand | [keep current] | [keep current] |
| Ask | Your answer appears here. | Type your question above, then press ⌘↵. |

## 4. Implementation paths (pick one by stack)

**A. Web view or Electron/Tauri UI**
- Inline each SVG as is. The animation is CSS inside the SVG and already respects `prefers-reduced-motion`.

**B. Native SwiftUI or AppKit** (likely for Per My Last)
- SwiftUI cannot play animated SVG. Use one of these:
  1. **Layered assets (recommended).** Split each SVG into a static background plus the moving groups listed in section 5. Export each as a vector PDF in the asset catalogue with "Preserve Vector Data" on, then animate the layers with SwiftUI `rotationEffect` and `offset`.
  2. **Lottie.** Convert the SVGs to Lottie JSON (a designer's task, done in After Effects plus Bodymovin, or LottieFiles) and play them with `lottie-ios`. Adds one dependency.
  3. **Static fallback.** Ship a static PDF only. Acceptable for a first release.

## 5. Motion spec (what moves, per asset)

All loops use `ease-in-out` and loop forever. Amplitudes are small on purpose: the panel should feel calm.

| Asset | Element (SVG class) | Motion | Pivot | Duration |
|---|---|---|---|---|
| Reply | Umbrella canopy (`.flap`) | Breathes vertically, scaleY 1 to 1.12 | Canopy centre-top (120, 40) | 2.4s |
| Reply | Shore wave (`.wave`) | Drifts horizontally, 0 to −6 | n/a | 4s |
| Write | Umbrella (`.sway`) | Rotates 0° to −1.5° | Pole foot. On screen (104, 104); the group sits inside a scale transform, so in local coordinates it is (168, 124) | 5s |
| Write | Shore wave (`.wave`) | Drifts horizontally, 0 to −6 | n/a | 4s |
| Understand | Umbrella (`.sway`) | Rotates 0° to −1.5° | Pole foot (112, 104) | 5s |
| Ask | Hammock (`.swing`) | Rotates −0.8° to +0.8° | (120, 56) | 4s |
| Ask | Left palm fronds (`.frondL`) | Rotate 0° to 2.5° | Top-left corner (4, −4) | 5s |
| Ask | Right palm fronds (`.frondR`) | Rotate 0° to −2.5° | Top-right corner (236, −4) | 5.4s |
| Ask | Birds (`.bird`) | Drift (−6, −2) and back; second bird delayed 1.5s | n/a | 6s |

**Rules**
- **Reduce Motion:** when on, show a static frame with nothing moving.
- **Pause when off screen:** stop the animation when the panel is hidden, the window is in the background, or the mode is not visible. This saves CPU.
- **When it plays:** the illustration shows only in the idle state. It fades out over 0.18s when loading starts.

## 6. Colours and dark mode

- **Brand colours:** the blues are Per My Last tokens: `accent` #2b6cf6, `accent-hover` #1f5bd8, `accent-text` (dark) #7aa2ff, `accent-soft` #f0f5ff.
- **Colours not in the design system:** add these as illustration tokens rather than hard-coding them.

| Proposed token | Light | Used for |
|---|---|---|
| `illustration-sky` | #f0f5ff | Sky (Reply, Write) |
| `illustration-sea` | #c7d9ff | Sea body (Reply, Write) |
| `illustration-sea-far` | #9dbbff | Band below the horizon (Reply, Write) |
| `illustration-sea-sunset` | #8fb0f5 | Sea at sunset (Ask) |
| `illustration-sand` | #f3ecdc | Sand (Reply, Write, Understand) |
| `illustration-sand-sunset` | #f3e2c8 | Sand at sunset (Ask) |
| `illustration-sand-shade` | #e6dcc4 | Shadows on sand (Ask uses #e6d0ae) |
| `illustration-sunset-top` / `-mid` / `-bottom` | #f4f0fa / #fdf0e4 / #fde1c8 | Ask sky gradient (soft, not saturated) |
| `illustration-sun` | #ffb57a | Ask sun, a flat half disc on the horizon with no glow |
| `illustration-sun-glint` | #ffd2a0 | Sun reflection lines on the sea |
| `illustration-island` | #c4b0d6 | Distant island (Ask) |
| `illustration-silhouette` | #3f3f46 | Palm trunks and fronds |

- **Dark mode:** every token above needs a dark value, chosen by the designer. Until those exist, render the illustration at full colour on the dark panel.
  - The scenes have their own rounded "window" background, so they read fine on dark.
  - Never invert the illustration's colours.
- **Design-system rule change:** the design system currently says "Use no other illustration." This feature needs that rule amended, plus an Illustration section listing these four scenes.

## 7. Accessibility

- Each illustration is decorative next to the title. Mark it hidden from VoiceOver (`accessibilityHidden(true)` or `aria-hidden`), or keep the short label already in each SVG's `aria-label`. Do not do both.
- Nothing in the illustration carries meaning that the title and hint don't already state.

## 8. Acceptance criteria

1. **Assets:** each mode's empty state shows its mapped illustration, title and hint, centred as in section 2.
2. **Motion:** the illustration animates as in section 5 and stops completely with Reduce Motion on.
3. **CPU:** the animation pauses when the window is hidden or the mode isn't visible. CPU stays near idle.
4. **Sharpness:** the illustration is crisp at 1× and 2× (vector, no blurry bitmaps).
5. **Transitions:** switching modes swaps the illustration without layout shift.
6. **Dark mode:** the illustrations render without inverted colours.
7. **Code:** no hard-coded hex values in the code; colours come from tokens, or stay inside the SVG asset.
