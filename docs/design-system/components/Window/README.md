The popup, composed. It docks to the right half of the screen, full height, on whichever display holds the cursor, and re-docks every time it opens. Its minimum size is `layout-popup-min-width` by `layout-popup-min-height`.

Reading order, top to bottom of the content column: mode title and description (wide layout), source box, preset chips, the collapsed Prompt row with the tone, the Send button (or the intent field with Send beside it on Reply), the output panel. The footer carries the version and Send feedback, plus the credits badge when the user is on credits. The shortcut-conflict and account banners sit above everything.

- Ask replaces the source box, chips and Prompt row with one question box, and keeps Send and the output panel.
- Escape hides the popup; ⌘↵ sends from anywhere in it.
- Settings replaces the popup in place and restores it on close.
- One solid `accent` element per view: Send. Everything else that is selected uses `accent-soft`.
- Window and card corners follow `radius-window` and `radius-card`; keep nested corners concentric.