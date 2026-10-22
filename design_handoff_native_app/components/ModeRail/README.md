The mode navigation for the popup: Reply, Write, Understand and a fixed last tab, Ask.

**Two layouts, one component.** Below `layout-rail-breakpoint` (640px of window content) it is a horizontal tab strip: label only, the selected tab marked by a 2px `accent` underline. At 640px and above it becomes a left rail `layout-rail-width` wide: icon, label and a one-line hint per mode, the selected item on `accent-soft` with `accent-text`. The eyebrow "What are you trying to do?" and the Settings button appear in the rail only in the wide layout.

**The consumer provides** the list of modes (user-owned, renamable) and the active one. Built-in modes (Reply, Write, Understand, Ask) get an icon and a hint; a custom mode shows its name alone, so the component must work without an icon or hint.

- Ask is always last, cannot be renamed, deleted or reordered, and is not a user mode.
- Selected state is shown by fill, weight and mark together, never by colour alone.
- Remember the last used mode and reopen on it.
- Arrow keys (up and down in the rail, left and right in the strip) move between modes.
- Keep `accent` fills to one element per view; the rail uses `accent-soft`, so Send keeps the only solid accent.