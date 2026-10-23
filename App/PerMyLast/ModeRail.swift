import SwiftUI

/// Mode navigation for the popup: a tab strip when narrow, a left rail when wide.
/// The consumer provides the modes (user-owned, renamable) and the active one; Ask is always last.
struct ModeRail: View {
    let modes: [String]
    @Binding var selection: String
    let wide: Bool
    var onSettings: () -> Void
    /// Wide rail only: collapses the sidebar. Nil hides the button.
    var onToggleSidebar: (() -> Void)? = nil

    @FocusState private var focused: Bool
    /// The ring is for keyboard navigation only; a mouse click must not leave an outline behind.
    @State private var keyboardNav = false

    private var all: [String] { modes + [AppModel.askTab] }

    var body: some View {
        Group { wide ? AnyView(rail) : AnyView(strip) }
    }

    /// Arrow keys move between modes; the ring marks the selected mode while the list has focus.
    private func keyboard<V: View>(_ view: V) -> some View {
        view
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(wide ? .upArrow : .leftArrow) { keyboardNav = true; move(-1); return .handled }
            .onKeyPress(wide ? .downArrow : .rightArrow) { keyboardNav = true; move(1); return .handled }
    }

    private func ring(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: PMLRadius.card + 2, style: .continuous)
            .strokeBorder(PMLColor.focusRing, lineWidth: 2)
            .padding(-2)
            .opacity(selected && focused && keyboardNav ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func move(_ delta: Int) {
        guard let i = all.firstIndex(of: selection) else { return }
        selection = all[min(max(i + delta, 0), all.count - 1)]
    }

    // MARK: Wide: left rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s1) {
            if let onToggleSidebar {
                HStack { Spacer(); SidebarToggleButton(collapsed: false, action: onToggleSidebar) }
            }
            Text("What are you trying to do?").pmlEyebrow()
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PMLSpace.s2)
            .padding(.bottom, PMLSpace.s3)
            keyboard(VStack(alignment: .leading, spacing: PMLSpace.s1) {
            ForEach(all, id: \.self) { mode in
                let selected = mode == selection
                Button { keyboardNav = false; selection = mode } label: {
                    HStack(spacing: PMLSpace.s2 + 2) {
                        if let icon = Self.icon(for: mode) {
                            Image(systemName: icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selected ? PMLColor.accentText : PMLColor.inkMuted)
                                .frame(width: 18)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            label(mode).font(PMLFont.tab).fontWeight(selected ? .bold : .semibold)
                                .foregroundStyle(selected ? PMLColor.accentText : PMLColor.ink)
                            if let summary = Self.summary(for: mode) {
                                Text(summary).font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, PMLSpace.s2 + 2).padding(.horizontal, PMLSpace.s2 + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(selected ? PMLColor.accentSoft : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(RailItemStyle())
                .overlay(ring(selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            })
            Spacer(minLength: 0)
        }
    }

    // MARK: Narrow: tab strip

    private var strip: some View {
        HStack(alignment: .bottom, spacing: PMLSpace.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                keyboard(HStack(spacing: PMLSpace.s4) {
                    ForEach(all, id: \.self) { mode in
                        let selected = mode == selection
                        Button { keyboardNav = false; selection = mode } label: {
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
                        .overlay(ring(selected))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                })
                .padding(.horizontal, 2)
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

    /// One line under a built-in mode's name: the job it does, at a glance. A custom mode has none.
    static func summary(for mode: String) -> LocalizedStringKey? {
        switch mode {
        case "Reply": "Answer a message you got"
        case "Write": "Say something new, polished"
        case "Understand": "Make sense of a message"
        case AppModel.askTab: "Get advice on tone or wording"
        default: nil
        }
    }

    /// The sentence under the heading of a built-in mode; a custom mode falls back to the app's tagline.
    static func blurb(for mode: String) -> LocalizedStringKey {
        switch mode {
        case "Reply": "Paste the message you got and say what you want to answer. Get a reply in your tone."
        case "Write": "Tell me what you need to say. Get a clear draft in the voice you pick."
        case "Understand": "Paste a message that confuses you. Get what it means and what it wants from you."
        case AppModel.askTab: "Ask about tone, wording or what to say next."
        default: "Say what you mean, but professionally. Saving careers, one email, one message at a time."
        }
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

/// Collapses or expands the sidebar (⌘/), the same control in both states.
struct SidebarToggleButton: View {
    let collapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "sidebar.left").font(.system(size: 14)) }
            .buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkSoft))
            .keyboardShortcut("/", modifiers: .command)
            .help(collapsed ? "Open sidebar (⌘/)" : "Close sidebar (⌘/)")
            .accessibilityLabel(Text(collapsed ? "Open sidebar" : "Close sidebar"))
    }
}
