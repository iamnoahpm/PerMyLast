Per My Last rewrites, explains and answers the messages people dread sending. The interface is quiet, so the person's own words stay the loudest thing on screen. Everything below applies to the macOS app first and to iPhone later.

## Content fundamentals

- Speak as the product to one person, plainly. Never "I" in controls; the product may say "I" only inside Ask and result text. Examples in the app today: "What are you trying to do?", "Your draft appears here.", "Tell me what you need to say."
- Sentence case everywhere: labels, buttons, tabs, headings. Uppercase appears only in the `eyebrow` and `badge` styles, set by the style, not typed.
- Buttons are a verb first, one to three words, no full stop: Send, Send again, Regenerate, Copy, Open Settings, Send feedback.
- Errors start with "Error:", say what happened and what to do, in one sentence. No exception text, no apologies.
- Hints are a short sentence under the control, ending with a full stop. Placeholders show a real example ("Confirm I can make it, but ask to push 30 minutes").
- No em dashes in the interface or in model output the app requests. Use a full stop or a colon.
- No emoji as decoration. Emoji appear only as the icon a person chose for their own preset (🤴 Like Brit., 🫆 Like Me).
- The words people see for modes are Reply, Write, Understand and Ask. Presets keep the names the person gave them.

## Visual foundations

- **Colour.** Neutral first. Text is `ink`, `ink-soft` or `ink-muted` on `surface`, `surface-sunken` or `surface-inset`. One blue, `accent`, is the only saturated colour; it fills Send and the selected-segment marks, and appears as text only through `accent-text`. `ink-hint` is for placeholders and decorative marks and never for text that carries meaning. Semantic colours (`success`, `danger`, `warning` with their `-soft` grounds) always come with a word.
- **Themes.** Light and dark are both first-class and use the same token names. Never hard-code a colour; resolve a token. In dark, `accent` stays the same fill and `accent-text` lightens.
- **Type.** Plus Jakarta Sans for everything, JetBrains Mono for key hints only. Use the named styles (`page-title`, `card-title`, `tab`, `input`, `body`, `select`, `meta`, `hint`, `eyebrow`, `badge`) and no sizes outside them. Two weights do most of the work: 400 to 500 for reading, 700 for titles and selected states.
- **Space.** A 4px base: `space-1` to `space-7`. Window padding is `layout-window-padding` (20px). Gap between sections of the popup is `space-4`; between a label and its control `space-2`.
- **Shape.** Corners come from `radius-*`: `radius-window` for the window, `radius-card` for panels and rail items, `radius-inset` for the intent field and Send, `radius-input` for inputs, `radius-btn` for small buttons, `radius-pill` for chips. Nested corners stay concentric.
- **Elevation.** Mostly flat. Panels use a 1px `line` or `divider` outline; only the floating window and popovers use `shadow-window` and `shadow-card-lg`. Selected state is never a shadow.
- **Layout.** The popup docks to the right half of the screen. From 640px of content width the mode tabs become a left rail (`layout-rail-width`); below that they are a tab strip. The window never goes below `layout-popup-min-width` by `layout-popup-min-height`.
- **Motion.** Short and calm: 0.18s for hover and small state, 0.24s for panels, easing `cubic-bezier(.2, .8, .2, 1)`. Primary buttons lift 1px on hover. Respect Reduce Motion by removing the lift and cross-fading instead.
- **States.** Hover changes fill, not size. Focus is a 2px `focus-ring` outline offset 2px on every interactive element. Disabled controls stay visible and say why in a tooltip. Selected is shown by fill, weight and a mark together.
- **Accessibility.** Text meets 4.5:1 on the grounds named in its token note, in both themes; `ink-hint` and disabled labels are the documented exceptions. Never rely on colour alone. All controls are reachable by keyboard; arrow keys move within the mode list.

## Iconography

- Mode icons are simple 2px-stroke outline glyphs with round caps, 17px in the rail: Reply (arrow turning back), Write (pencil), Understand (lightbulb), Ask (speech bubble with a question mark). On Apple platforms use SF Symbols with the same meaning at the same weight: `arrowshape.turn.up.left`, `pencil`, `lightbulb`, `questionmark.bubble`; a custom mode has no icon.
- The brand mark is an umbrella. The app icon is the full-colour umbrella tile. The menu bar icon is a single-colour template image: solid open umbrella when the app is enabled, outlined tilted umbrella when disabled (assets in Brand).
- The only illustrations are the four empty-state scenes below. Use no other illustration. Every other empty state is one sentence of text.

## Illustration

The empty output panel shows one animated beach scene per mode, 200 × 110 pt (20:11, never below 160 pt wide), above the title and hint. Colours are the `illustration-*` tokens and are never inverted in dark mode. Motion is slow and loops forever, stops under Reduce Motion, and pauses when the panel is hidden. Spec: `docs/REQUIREMENT-empty-states.md`.

| Mode | Scene |
|---|---|
| Reply | One umbrella, two deckchairs close to the pole, facing the sea |
| Write | One reclined striped lounger angled toward the sea, umbrella planted behind it |
| Understand | An upright striped umbrella planted behind a full deckchair in 3/4 view, flat icon style |
| Ask | An empty hammock between two leaning palm trunks at a soft sunset |
