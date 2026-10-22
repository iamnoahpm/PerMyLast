# SwiftUI mapping

How to build this system in the native app. `DesignTokens.swift` is generated from `tokens.json`; regenerate it instead of editing it.

## Tokens to Swift

| Token family | Swift | Notes |
| --- | --- | --- |
| color | `PMLColor.surface`, `.ink`, `.accent`, and so on | Dynamic colours that follow light and dark. Use them instead of `Color.accentColor`, `.secondary` and system greys. |
| spacing | `PMLSpace.s1` to `.s7` | `s3` = 12, `s4` = 16, `s5` = 24. |
| radius | `PMLRadius.window`, `.card`, `.inset`, `.input`, `.btn`, `.seg`, `.badge`, `.pill` | Use `RoundedRectangle(cornerRadius:style: .continuous)`. |
| type | `PMLFont.pageTitle`, `.input`, `.body`, and so on | Bundle Plus Jakarta Sans (OFL) and register it in Info.plist (`ATSApplicationFontsPath`). Without it SwiftUI falls back to the system font. |
| layout | `PMLLayout.railWidth`, `.railBreakpoint`, `.popupMinWidth`, `.popupMinHeight` | |
| motion | `PMLMotion.fast`, `.base` | Remove the 1pt hover lift when Reduce Motion is on. |

## Component to SwiftUI

| Component | Build it as | Replace |
| --- | --- | --- |
| ModeRail | A custom view: `HStack` of tab buttons below `railBreakpoint` points, otherwise `VStack` in a fixed-width left column. Read the width with `GeometryReader` or `ViewThatFits`. | The segmented `Picker` in `MainView.tabs(selection:)` |
| PresetChip | A `Button` with `Capsule()` background, `ButtonStyle` using `accentSoft` and a 1.5pt `accent` stroke when selected. Lay out with the existing `FlowLayout`. | The current chip buttons |
| Field | `TextEditor` on a `RoundedRectangle` filled `surfaceSunken`, hide the system background with `.scrollContentBackground(.hidden)`, focus ring via `@FocusState`. | System bordered text views |
| Button | A `ButtonStyle` per variant: `PMLPrimaryButtonStyle` (Send), `.secondary`, `.ghost`. | `.borderedProminent` and `.borderless` |
| OutputPanel | A `VStack` in a `RoundedRectangle` with `surfaceInset` (empty) or `surface` (filled). | `OutputPanel` styling |
| Banner | An `HStack` on `warningSoft` with a `warningLine` stroke. | `ShortcutWarningBanner`, `AccountWarningBanner` styling |
| TrayMenu | Keep `NSMenu`: Enabled, Show in Dock, separator, Settings…, Check for Updates…, separator, Quit Per My Last. Left-click opens the popup; show the menu on right-click only. | `StatusItemController` menu |
| Window | Dock right half of the screen, `PMLRadius.window` corners, `.windowStyle(.hiddenTitleBar)` is optional; keep the system traffic lights. | |

## Rules for the build

- Never use a colour literal or a system colour for text or fills in app views; use `PMLColor`.
- Never use a font size outside `PMLFont`.
- Send is the only `accent` filled control in a view.
- Ship light and dark together and check both.
- Keep behaviour exactly as it is today (Ask tab, presets, Write My Way, Prompt panel, credits badge); this is a visual and layout change.
