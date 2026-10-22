import CoreText
import Foundation
import SwiftUI

/// Registers the bundled Plus Jakarta Sans variable font for this process, so
/// `PMLFont` resolves without an `ATSApplicationFontsPath` Info.plist entry.
enum PMLFontRegistration {
    static func register() {
        guard let url = Bundle.main.url(forResource: "PlusJakartaSans", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

#if DEBUG
/// Light and dark swatches for every colour token.
#Preview("Colour tokens") {
    let swatches: [(String, Color)] = [
        ("surface", PMLColor.surface), ("surfaceSunken", PMLColor.surfaceSunken), ("surfaceInset", PMLColor.surfaceInset),
        ("ink", PMLColor.ink), ("inkSoft", PMLColor.inkSoft), ("inkMuted", PMLColor.inkMuted), ("inkHint", PMLColor.inkHint),
        ("line", PMLColor.line), ("lineStrong", PMLColor.lineStrong), ("divider", PMLColor.divider),
        ("accent", PMLColor.accent), ("accentHover", PMLColor.accentHover), ("accentText", PMLColor.accentText), ("accentSoft", PMLColor.accentSoft),
        ("success", PMLColor.success), ("danger", PMLColor.danger), ("warning", PMLColor.warning), ("warningSoft", PMLColor.warningSoft),
    ]
    return VStack(spacing: 0) {
        ForEach(["light", "dark"], id: \.self) { scheme in
            HStack(spacing: 4) {
                ForEach(swatches, id: \.0) { name, color in
                    RoundedRectangle(cornerRadius: PMLRadius.badge).fill(color).frame(width: 28, height: 28).help(name)
                }
            }
            .padding(PMLSpace.s3)
            .background(PMLColor.surface)
            .environment(\.colorScheme, scheme == "dark" ? .dark : .light)
        }
    }
}
#endif
