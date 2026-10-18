# Per My Last (native)

Native Swift rewrite of Per My Last, for macOS first, then iPhone (and later
Apple Watch). The previous Electron app lives on in
`iamnoahpm/PerMyLast` (branch `electron-legacy`, tag `electron-v1.1.0-final`)
as the base for any future Windows/Linux port.

## Layout

- `Packages/PerMyLastCore` — shared logic, no UI: Anthropic client, presets and
  tabs, prompt building, language list, wartime/peacetime profiles. Builds for
  macOS 14+, iOS 17+, watchOS 10+.
- `App/` — (not created yet) the Xcode project: macOS menu bar app first.

## Develop

```bash
cd Packages/PerMyLastCore
swift test
```

## Not ported yet

From the Electron app: the "Write my way" settings (tone, length, format,
English level), shortcut-conflict detection, English/Vietnamese UI strings
(`renderer/i18n.js`), settings storage, and all UI.
