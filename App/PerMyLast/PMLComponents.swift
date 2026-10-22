import SwiftUI

// Shared pieces of the Per My Last design system: button styles, chip style, fields, panels.
// Exact fills, radii and states follow docs/design-system/components/*/README.md.

// MARK: - Focus ring

private struct PMLFocusRing: ViewModifier {
    let radius: CGFloat
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                .strokeBorder(PMLColor.focusRing, lineWidth: 2)
                .padding(-4)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false))
    }
}

extension View {
    /// 2px `focusRing` outline offset 2px, shown for keyboard focus.
    func pmlFocusRing(radius: CGFloat) -> some View { modifier(PMLFocusRing(radius: radius)) }
}

// MARK: - Buttons

enum PMLButtonSize {
    case regular, compact
    var height: CGFloat { self == .regular ? PMLLayout.controlHeight : 28 }
    var radius: CGFloat { self == .regular ? PMLRadius.inset : PMLRadius.btn }
    var hPadding: CGFloat { self == .regular ? PMLSpace.s4 : PMLSpace.s3 }
}

/// The one accent-filled action per view (Send).
struct PMLPrimaryButtonStyle: ButtonStyle {
    var size: PMLButtonSize = .regular
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let lift = hovering && isEnabled && !reduceMotion
        configuration.label
            .font(PMLFont.select.weight(.bold))
            .foregroundStyle(isEnabled ? PMLColor.onAccent : PMLColor.inkHint)
            .padding(.horizontal, size.hPadding)
            .frame(minHeight: size.height)
            .background(
                RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                    .fill(!isEnabled ? PMLColor.disabledFill : (hovering || configuration.isPressed ? PMLColor.accentHover : PMLColor.accent)))
            .pmlFocusRing(radius: size.radius)
            .offset(y: lift ? PMLMotion.lift : 0)
            .animation(PMLMotion.fast, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Outlined on `surface`: Regenerate, Cancel.
struct PMLSecondaryButtonStyle: ButtonStyle {
    var size: PMLButtonSize = .compact
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PMLFont.select)
            .foregroundStyle(isEnabled ? PMLColor.ink : PMLColor.inkHint)
            .padding(.horizontal, size.hPadding)
            .frame(minHeight: size.height)
            .background(
                RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                    .fill(hovering || configuration.isPressed ? PMLColor.surfaceSunken : PMLColor.surface))
            .overlay(RoundedRectangle(cornerRadius: size.radius, style: .continuous).strokeBorder(PMLColor.lineStrong, lineWidth: 1))
            .pmlFocusRing(radius: size.radius)
            .animation(PMLMotion.fast, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Secondary shape filled with `ink`: Copy.
struct PMLInkButtonStyle: ButtonStyle {
    var size: PMLButtonSize = .compact
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PMLFont.select)
            .foregroundStyle(PMLColor.surface)
            .padding(.horizontal, size.hPadding)
            .frame(minHeight: size.height)
            .background(
                RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                    .fill(PMLColor.ink.opacity(!isEnabled ? 0.35 : (hovering || configuration.isPressed ? 0.85 : 1))))
            .pmlFocusRing(radius: size.radius)
            .animation(PMLMotion.fast, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Text that gains a fill on hover: low-weight actions.
struct PMLGhostButtonStyle: ButtonStyle {
    var size: PMLButtonSize = .compact
    var tint: Color = PMLColor.accentText
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PMLFont.select)
            .foregroundStyle(isEnabled ? tint : PMLColor.inkHint)
            .padding(.horizontal, size.hPadding - 4)
            .frame(minHeight: size.height - 4)
            .background(
                RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                    .fill(hovering || configuration.isPressed ? PMLColor.surfaceSunken : .clear))
            .pmlFocusRing(radius: size.radius)
            .animation(PMLMotion.fast, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Preset chip: `surfaceSunken` at rest; selected gets an `accentSoft` fill, 1.5pt `accent` outline and `accentText` label.
struct PMLChipStyle: ButtonStyle {
    var selected: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PMLFont.select)
            .foregroundStyle(selected ? PMLColor.accentText : PMLColor.ink)
            .padding(.horizontal, PMLSpace.s3)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? PMLColor.accentSoft : (hovering ? PMLColor.lineStrong : PMLColor.surfaceSunken)))
            .overlay(Capsule().strokeBorder(selected ? PMLColor.accent : .clear, lineWidth: 1.5))
            .pmlFocusRing(radius: 16)
            .animation(PMLMotion.fast, value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Panels and fields

/// A card: `surface` with a hairline `line` outline, or `surfaceInset` for quiet read-outs.
struct PMLPanel<Content: View>: View {
    var fill: Color = PMLColor.surface
    var radius: CGFloat = PMLRadius.card
    var padding: CGFloat = PMLSpace.s3
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(PMLColor.line, lineWidth: 1))
    }
}

/// Warning/error banner ground: `warningSoft` with a `warningLine` outline.
struct PMLBanner<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(PMLSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.warningSoft))
            .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(PMLColor.warningLine, lineWidth: 1))
    }
}

/// Multi-line field: `surfaceSunken` with no border; on focus `surface` with a 1px `accent` border.
struct PMLField: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey
    var minHeight: CGFloat = 150
    var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(PMLFont.input)
                .foregroundStyle(PMLColor.ink)
                .scrollContentBackground(.hidden)
                .padding(PMLSpace.s2)
            if text.isEmpty {
                Text(placeholder)
                    .font(PMLFont.input)
                    .foregroundStyle(PMLColor.inkHint)
                    .padding(.horizontal, 13).padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(isFocused ? PMLColor.surface : PMLColor.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(isFocused ? PMLColor.accent : .clear, lineWidth: 1))
        .animation(PMLMotion.fast, value: isFocused)
    }
}

/// Single-line field: `line-strong` border on `surface`; `accent` border on focus.
struct PMLTextFieldStyle: TextFieldStyle {
    var radius: CGFloat = PMLRadius.inset
    var height: CGFloat? = nil
    @FocusState private var focused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(PMLFont.input)
            .foregroundStyle(PMLColor.ink)
            .focused($focused)
            .padding(.horizontal, PMLSpace.s3)
            .frame(minHeight: height ?? 32)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(PMLColor.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(focused ? PMLColor.accent : PMLColor.lineStrong, lineWidth: 1))
    }
}

extension View {
    /// `eyebrow` style: uppercase, tracked, `accentText`.
    func pmlEyebrow(_ color: Color = PMLColor.accentText) -> some View {
        font(PMLFont.eyebrow).tracking(0.77).textCase(.uppercase).foregroundStyle(color)
    }
}
