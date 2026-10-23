Text entry. Three forms share one look: the **source box** (text to rewrite or explain, with a live word count), the **question box** used by Ask (labelled "Your question"), and the single-line **intent field** that sits beside Send on Reply.

- The source and question boxes sit on `surface-sunken` with no border; on focus they move to `surface` with a 1px `accent` border. The intent field has a `line-strong` border on `surface`.
- Placeholder text is `ink-hint`: it is a prompt, not information. The shortcut in the source placeholder shows the user's real shortcut.
- Typed text is the `input` style, 13.5px.
- Pasted and captured text is cleaned (duplicate lines and runs of blank lines collapsed) before it is shown.
- The source box takes focus every time the popup opens; Ask focuses its question box.
- The word count is `ink-muted`, bottom right, hidden when empty.