Where the result lands. Three states: **empty** (a centred hint on `surface-inset`), **filled** (a header row with the action name and tone in the `eyebrow` style, Regenerate and Copy on the right, the result below in the `input` style on `surface`) and **error** (one line in `danger` that starts with "Error:" and ends with a Retry link).

- Show the action name and tone in the header so a result is never ambiguous about how it was made.
- Copy reads "Copied" for about 1.5 seconds, then returns.
- Editing the source text does not clear an existing result; only Send or Regenerate replaces it.
- Errors say what happened and what to do next, in one sentence. Never show raw exception text.
- Results are selectable text and keep the line breaks the model returned.