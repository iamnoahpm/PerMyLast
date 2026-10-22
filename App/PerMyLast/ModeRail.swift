import SwiftUI

/// Mode navigation for the popup: a tab strip when narrow, a left rail when wide.
/// The consumer provides the modes (user-owned, renamable) and the active one; Ask is always last.
struct ModeRail: View {
    let modes: [String]
    @Binding var selection: String
    let wide: Bool
    var onSettings: () -> Void

    @FocusState private var focused: Bool

    private var all: [String] { modes + [AppModel.askTab] }

    var body: some View {
        Group { wide ? AnyView(rail) : AnyView(strip) }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(wide ? .upArrow : .leftArrow) { move(-1); return .handled }
            .onKeyPress(wide ? .downArrow : .rightArrow) { move(1); return .handled }
    }

    private func move(_ delta: Int) {
        guard let i = all.firstIndex(of: selection) else { return }
        selection = all[min(max(i + delta, 0), all.count - 1)]
    }

    // MARK: Wide: left rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s1) {
            HStack(alignment: .top) {
                Text("What are you trying to do?").pmlEyebrow()
                Spacer(minLength: PMLSpace.s2)
                settingsButton
            }
            .padding(.bottom, PMLSpace.s2)
            ForEach(all, id: \.self) { mode in
                let selected = mode == selection
                Button { selection = mode } label: {
                    HStack(spacing: PMLSpace.s2) {
                        Capsule().fill(selected ? PMLColor.accentText : .clear).frame(width: 3, height: 16)
                        if let icon = Self.icon(for: mode) {
                            Image(systemName: icon).font(.system(size: 14, weight: selected ? .bold : .regular)).frame(width: 18)
                        }
                        label(mode).font(PMLFont.tab).fontWeight(selected ? .bold : .semibold)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? PMLColor.accentText : PMLColor.ink)
                    .padding(.vertical, PMLSpace.s2).padding(.trailing, PMLSpace.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(selected ? PMLColor.accentSoft : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(RailItemStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Narrow: tab strip

    private var strip: some View {
        HStack(alignment: .bottom, spacing: PMLSpace.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PMLSpace.s4) {
                    ForEach(all, id: \.self) { mode in
                        let selected = mode == selection
                        Button { selection = mode } label: {
                            label(mode)
                                .font(PMLFont.tab).fontWeight(selected ? .bold : .semibold)
                                .foregroundStyle(selected ? PMLColor.accentText : PMLColor.inkSoft)
                                .padding(.vertical, PMLSpace.s2)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(selected ? PMLColor.accent : .clear).frame(height: 2)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            settingsButton.padding(.bottom, 2)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(PMLColor.divider).frame(height: 1).offset(y: 0) }
    }

    private var settingsButton: some View {
        Button(action: onSettings) { Image(systemName: "gearshape").font(.system(size: 14)) }
            .buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkSoft))
            .help("Settings")
    }

    // The user's own mode names are shown as typed; Ask is a localised built-in.
    @ViewBuilder private func label(_ mode: String) -> some View {
        if mode == AppModel.askTab { Text("Ask") } else { Text(verbatim: mode) }
    }

    /// Built-in modes get an SF Symbol; a custom mode shows its name alone.
    static func icon(for mode: String) -> String? {
        switch mode {
        case "Reply": "arrowshape.turn.up.left"
        case "Write": "pencil"
        case "Understand": "lightbulb"
        case AppModel.askTab: "questionmark.bubble"
        default: nil
        }
    }
}

private struct RailItemStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(hovering ? PMLColor.surfaceSunken : .clear))
            .onHover { hovering = $0 }
    }
}
