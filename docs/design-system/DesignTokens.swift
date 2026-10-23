// Per My Last design tokens. Generated from tokens.json; do not edit by hand.
// Colors resolve per appearance (light / dark) on macOS and iOS.
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum PMLColor {
    /// Light and dark sRGB hex values, 0xRRGGBB.
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
        #else
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }

    /// Window and card background. Every text token below is checked against it.
    static let surface = dynamic(0xFFFFFF, 0x1C1C1F)
    /// Fill of text inputs, segmented-control tracks and chips at rest. Text on it: ink, ink-soft, ink-muted.
    static let surfaceSunken = dynamic(0xF2F2F5, 0x27272B)
    /// Quiet panels inside a window: the prompt read-out, the empty output panel. Text on it: ink, ink-soft, ink-muted.
    static let surfaceInset = dynamic(0xF6F6F8, 0x222225)
    /// Primary text and icons on surface, surface-sunken, surface-inset and accent-soft.
    static let ink = dynamic(0x17171A, 0xF2F2F5)
    /// Body copy that supports a heading, prompt text. On surface, surface-sunken, surface-inset.
    static let inkSoft = dynamic(0x4A4A52, 0xC4C4CC)
    /// Secondary text: hints under controls, meta rows, rail hints. On surface, surface-sunken, surface-inset. The lightest grey allowed for text that carries meaning.
    static let inkMuted = dynamic(0x6B6B73, 0xA0A0A8)
    /// Placeholders and decorative marks only (2.8:1 on surface in light, below the 4.5:1 text floor). Never for text a person must read.
    static let inkHint = dynamic(0x9A9AA2, 0x75757D)
    /// Window and card outlines. Decorative separation, not a control boundary.
    static let line = dynamic(0xE4E4E9, 0x34343A)
    /// Outline of secondary buttons and unselected chips. Decorative; controls are also told apart by fill and label.
    static let lineStrong = dynamic(0xDEDEE3, 0x3F3F46)
    /// Hairlines between sections and under the footer.
    static let divider = dynamic(0xECECF0, 0x2A2A2E)
    /// Fill of the one primary action per view (Send), the selected segment and the selected rail item's mark. White (on-accent) text on it is 4.6:1 in both themes.
    static let accent = dynamic(0x2B6CF6, 0x2B6CF6)
    /// Hover and pressed fill of accent controls. On-accent text on it is 5.9:1.
    static let accentHover = dynamic(0x1F5BD8, 0x1F5BD8)
    /// Accent used as text or an icon: eyebrow, links, the selected chip's label, the selected rail item. On surface (5.9:1 light, 6.8:1 dark) and on accent-soft.
    static let accentText = dynamic(0x1F5BD8, 0x7AA2FF)
    /// Selected chip and selected rail item background. Pair with accent-text and ink.
    static let accentSoft = dynamic(0xF0F5FF, 0x1B2845)
    /// Text and icons on accent and accent-hover.
    static let onAccent = dynamic(0xFFFFFF, 0xFFFFFF)
    /// 2px keyboard focus ring, offset 2px. 4.6:1 or better against surface in both themes.
    static let focusRing = dynamic(0x2B6CF6, 0x7AA2FF)
    /// Saved flash and positive status text, always with a word. On surface, surface-sunken, surface-inset.
    static let success = dynamic(0x127A52, 0x4FC79A)
    /// Background of a success banner or pill. Pair with success.
    static let successSoft = dynamic(0xE7F4ED, 0x13352A)
    /// Errors and destructive text, always with a word. On surface and surface-inset.
    static let danger = dynamic(0xB3261E, 0xFF8F86)
    /// Background of an error banner. Pair with danger.
    static let dangerSoft = dynamic(0xFDF3F2, 0x3A1C1A)
    /// Shortcut-conflict and account warnings, always with a word. On warning-soft.
    static let warning = dynamic(0x8A6205, 0xF0C75E)
    /// Background of a warning banner. Pair with warning and ink.
    static let warningSoft = dynamic(0xFDF8EC, 0x3A2F10)
    /// Outline of a warning banner.
    static let warningLine = dynamic(0xF0DFB4, 0x5A4A1C)
    /// Fill of a disabled Send button. Its label uses ink-hint on purpose: disabled controls are exempt from the text floor.
    static let disabledFill = dynamic(0xE4E4E9, 0x34343A)
}

enum PMLSpace {
    /// Icon-to-label gap, tight stacks.
    static let s1 : CGFloat = 4
    /// Gap between chips, between a label and its control.
    static let s2 : CGFloat = 8
    /// Padding inside inputs and panels, gap between rows.
    static let s3 : CGFloat = 12
    /// Gap between sections of the popup.
    static let s4 : CGFloat = 16
    /// Window padding on wide layouts.
    static let s5 : CGFloat = 24
    /// Gap between the rail and the content column.
    static let s6 : CGFloat = 32
    /// Large breaks in settings pages.
    static let s7 : CGFloat = 48
}

enum PMLRadius {
    /// Chips and the Enabled badge.
    static let pill : CGFloat = 999
    /// Window and popup outer corners.
    static let window : CGFloat = 12
    /// Panels, output panel, banners, rail items.
    static let card : CGFloat = 10
    /// Prompt read-out, intent field.
    static let inset : CGFloat = 9
    /// Text inputs and selects.
    static let input : CGFloat = 8
    /// Buttons.
    static let btn : CGFloat = 7
    /// Segments inside a segmented control.
    static let seg : CGFloat = 6
    /// Badges.
    static let badge : CGFloat = 5
}

enum PMLLayout {
    /// Width of the mode rail on wide windows.
    static let railWidth : CGFloat = 210
    /// Window content width at which the tab strip becomes the rail.
    static let railBreakpoint : CGFloat = 640
    /// Narrowest the popup may be resized to.
    static let popupMinWidth : CGFloat = 380
    /// Shortest the popup may be resized to.
    static let popupMinHeight : CGFloat = 460
    /// Padding around popup content on narrow layouts.
    static let windowPadding : CGFloat = 20
    /// Send button and intent field height.
    static let controlHeight : CGFloat = 40
}

/// Type styles. Plus Jakarta Sans must be bundled (OFL, Google Fonts) and registered;
/// without it SwiftUI falls back to the system font at the same size and weight.
enum PMLFont {
    private static let family = "Plus Jakarta Sans"
    static let pageTitle = Font.custom(family, size: 17).weight(.bold)
    static let cardTitle = Font.custom(family, size: 14).weight(.bold)
    static let tab = Font.custom(family, size: 14).weight(.semibold)
    static let input = Font.custom(family, size: 13.5)
    static let body = Font.custom(family, size: 12.5)
    static let select = Font.custom(family, size: 13).weight(.medium)
    static let meta = Font.custom(family, size: 12)
    static let hint = Font.custom(family, size: 11.5)
    /// Apply `.textCase(.uppercase)` and `.tracking(0.77)` (0.07em).
    static let eyebrow = Font.custom(family, size: 11).weight(.bold)
    /// Apply `.textCase(.uppercase)` and `.tracking(0.42)` (0.04em).
    static let badge = Font.custom(family, size: 10.5).weight(.bold)
    static let kbd = Font.system(size: 12, weight: .medium, design: .monospaced)
}

/// Shadows, light/dark resolved by the caller through `colorScheme`.
enum PMLShadow {
    static func window(_ scheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) { (.black.opacity(scheme == .dark ? 0.6 : 0.28), 30, 24) }
    static func card(_ scheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) { (.black.opacity(scheme == .dark ? 0.4 : 0.03), 1, 1) }
    static func cardLarge(_ scheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) { (.black.opacity(scheme == .dark ? 0.45 : 0.07), 9, 6) }
}

/// Motion: 0.18s for hover and small state changes, 0.24s for panels. Hover lift is -1pt on buttons and cards.
enum PMLMotion {
    static let fast = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)
    static let base = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)
    static let lift: CGFloat = -1
}

#if canImport(AppKit)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif
