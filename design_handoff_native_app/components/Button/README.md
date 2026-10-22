Four buttons. **Send** is the one primary action per view: `accent` fill, `on-accent` label, `layout-control-height` high, with the ⌘↵ hint in the mono face. **Secondary** (Regenerate, Cancel) has a `line-strong` outline on `surface`. **Copy** is a secondary shape filled with `ink`. **Ghost** is text that gains a fill on hover, for low-weight actions.

- Never place two `accent` filled buttons in one view. Once a result exists, the Send label becomes "Send again".
- A disabled Send stays visible and explains itself in a tooltip (for example "Select or paste some text first"); disabled buttons are exempt from the text-contrast floor.
- Hover lifts a primary button 1px and darkens it to `accent-hover`; secondary and ghost only change fill.
- Labels are one to three words, verb first, sentence case, no full stop.
- Keyboard focus draws a 2px `focus-ring` outline offset by 2px.