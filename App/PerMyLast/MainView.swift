import PerMyLastCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool
    @FocusState private var askFocused: Bool
    @FocusState private var intentFocused: Bool
    /// Pinned: the rail is part of the layout. Unpinned: it hides, and slides over the content while the pointer is at the left edge.
    @AppStorage("railPinned") private var railPinned = true
    @State private var railPeek = false

    private let onboarding = OnboardingModel.shared

    var body: some View {
        if onboarding.isActive { OnboardingView() } else { mainContent }
    }

    private var mainContent: some View {
        @Bindable var model = model
        return GeometryReader { geo in
            let wide = geo.size.width >= PMLLayout.railBreakpoint
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    if wide && railPinned { railColumn }
                    ScrollView {
                        VStack(alignment: .leading, spacing: PMLSpace.s4) {
                            ShortcutWarningBanner()
                            AccountWarningBanner()
                            if !wide { SetupProgressCard() }
                            if !wide {
                                header
                                ModeRail(modes: model.modes, selection: $model.activeMode, wide: false) { WindowCoordinator.shared.showSettings() }
                            }
                            modeHeading
                            if model.isAsk {
                                SingleComposer(focus: $askFocused)
                            } else {
                                chips
                                if model.activeModeTakesIntent {
                                    ReplyComposer(theirFocus: $inputFocused, intentFocus: $intentFocused)
                                } else {
                                    SingleComposer(focus: $inputFocused)
                                }
                            }
                            OutputPanel()
                        }
                        .padding(.horizontal, wide ? PMLSpace.s5 : PMLLayout.windowPadding)
                        // Wide: the mode title shares a line with the sidebar's eyebrow.
                        .padding(.top, wide ? PMLSpace.s2 : PMLLayout.windowPadding)
                        .padding(.bottom, wide ? PMLSpace.s5 : PMLLayout.windowPadding)
                    }
                }
                .overlay(alignment: .leading) { if wide && !railPinned { peekRail } }
                Rectangle().fill(PMLColor.divider).frame(height: 1)
                FooterBar()
            }
            .overlay(alignment: .topLeading) { if wide { sidebarToggle } }
        }
        .background(PMLColor.surface)
        .frame(minWidth: PMLLayout.popupMinWidth, minHeight: PMLLayout.popupMinHeight)
        .navigationTitle("Per My Last")
        .onChange(of: model.activeMode) {
            model.selectDefaultPreset()
            if model.isAsk { askFocused = true }
        }
        .onChange(of: model.focusToken) {
            if model.isAsk { askFocused = true } else { inputFocused = true }
        }
        .onExitCommand { WindowCoordinator.shared.hidePopup() }
    }

    // MARK: Sidebar

    /// Modes, setup progress or plans, and the account: the whole left column.
    private var railColumn: some View {
        @Bindable var model = model
        return VStack(spacing: PMLSpace.s3) {
            ModeRail(modes: model.modes, selection: $model.activeMode, wide: true,
                     onSettings: { WindowCoordinator.shared.showSettings() })
            SetupProgressCard()
            PlansCard()
            AccountFooter()
        }
        .padding(PMLSpace.s3)
        .frame(width: PMLLayout.railWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PMLColor.surfaceInset)
        .overlay(alignment: .trailing) { Rectangle().fill(PMLColor.divider).frame(width: 1) }
    }

    /// In the title bar, on the traffic lights' line: at the sidebar's right edge while it is open,
    /// right after the traffic lights while it is hidden.
    private var sidebarToggle: some View {
        SidebarToggleButton(collapsed: !railPinned) {
            withAnimation(PMLMotion.base) { railPinned.toggle(); railPeek = false }
        }
        .padding(.leading, railPinned ? PMLLayout.railWidth - 50 : 78)
        .frame(height: 28)
        .offset(y: 2)
        .ignoresSafeArea()
    }

    /// While the rail is collapsed: a thin strip at the left edge reveals it on hover, and leaving it hides it again.
    private var peekRail: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(width: 10).frame(maxHeight: .infinity).contentShape(Rectangle())
                .onHover { if $0 { withAnimation(PMLMotion.base) { railPeek = true } } }
            if railPeek {
                railColumn
                    .shadow(color: .black.opacity(0.18), radius: 14, x: 4)
                    .transition(.move(edge: .leading))
                    .onHover { if !$0 { withAnimation(PMLMotion.base) { railPeek = false } } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Pieces

    private var header: some View {
        Text("What are you trying to do?").pmlEyebrow()
    }

    /// The active mode's name and what it does for you.
    private var modeHeading: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s1) {
            Group {
                if model.isAsk { Text("Ask") } else { Text(verbatim: model.activeMode) }
            }
            .font(.custom("Plus Jakarta Sans", size: 22).weight(.bold))
            .foregroundStyle(PMLColor.ink)
            Text(model.activeModeTakesIntent ? LocalizedStringKey("Their message and your intent live in one box.") : ModeRail.blurb(for: model.activeMode))
                .font(PMLFont.body)
                .foregroundStyle(PMLColor.inkSoft)
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            FlowLayout(spacing: 8) {
                ForEach(model.presetsInActiveMode) { preset in
                    let selected = preset.label == model.selectedLabel
                    Button {
                        model.select(preset)
                    } label: {
                        HStack(spacing: 5) {
                            if !preset.icon.isEmpty { Text(preset.icon) }
                            Text(preset.label)
                        }
                    }
                    .buttonStyle(PMLChipStyle(selected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { model.selectNeighbour(-1); return .handled }
            .onKeyPress(.rightArrow) { model.selectNeighbour(1); return .handled }
            if let preset = model.currentPreset, !preset.blurb.isEmpty {
                Text(model.blurb(for: preset)).font(PMLFont.meta).foregroundStyle(PMLColor.inkMuted)
            }
        }
    }
}

// MARK: - Output

struct OutputPanel: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        Group {
            if let error = model.errorMessage {
                errorBox(error)
            } else if model.hasResult {
                result
            } else if model.isSending {
                loadingState
            } else {
                emptyState
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.isSending)
    }

    /// Reply while the first words are still on their way.
    private var loadingState: some View {
        Text(LocalizedStringKey(model.isAsk ? "Writing your answer…" : (model.activeMode == "Understand" ? "Reading the message…" : "Writing your draft…")))
            .font(PMLFont.body).foregroundStyle(PMLColor.inkMuted)
            .frame(maxWidth: .infinity)
            .padding(PMLSpace.s5)
            .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.surfaceInset))
            .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(PMLColor.lineStrong, lineWidth: 1))
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var emptyState: some View { plainEmptyState }

    private var plainEmptyState: some View {
        VStack(spacing: PMLSpace.s1) {
            EmptyIllustration(scene: EmptyScene(mode: model.activeMode, isAsk: model.isAsk)).padding(.bottom, PMLSpace.s2)
            Text(LocalizedStringKey(model.isAsk ? "Your answer appears here." : (model.activeMode == "Understand" ? "Your explanation appears here." : "Your draft appears here."))).font(PMLFont.select).fontWeight(.bold).foregroundStyle(PMLColor.ink)
            Text(LocalizedStringKey(model.isAsk
                 ? "Type your question above, then press ⌘↵."
                 : (model.activeModeTakesIntent
                    ? "Paste their message, add your intent if you want, then press ⌘↵."
                    : "Pick a preset above, then press ⌘↵.")))
                .font(PMLFont.hint)
                .foregroundStyle(PMLColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: PMLSpace.s4, leading: PMLSpace.s4, bottom: 20, trailing: PMLSpace.s4))
        .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.surfaceInset))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous)
            .strokeBorder(PMLColor.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .transition(.opacity)
    }

    private func errorBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            Text("Error: \(message)")
                .font(PMLFont.body)
                .foregroundStyle(PMLColor.danger)
                .textSelection(.enabled)
            FlowLayout(spacing: PMLSpace.s1) {
                Button("Retry") { Task { await model.send() } }.disabled(!model.canSend)
                if model.lastErrorKind == .quotaExhausted, AccountModel.shared.entitlement?.ownsLifetime == true, !model.apiKey.isEmpty {
                    Button("Use my own API key instead") {
                        AccountModel.shared.useOwnKey = true
                        model.errorMessage = nil
                        Task { await model.send() }
                    }
                }
                if model.lastErrorKind == .updatesExpired {
                    Button("Renew updates →") { WindowCoordinator.shared.showPaywall() }
                }
                if model.lastErrorKind == .noEntitlement || model.lastErrorKind == .freeCreditsExhausted {
                    Button("See plans →") { WindowCoordinator.shared.showPaywall() }
                }
                if message == AnthropicError.missingAPIKey.errorDescription || model.lastErrorKind == .unauthenticated {
                    Button("Set up access →") { model.errorMessage = nil; OnboardingModel.shared.reopen(at: .access) }
                    Button("Open Settings →") { WindowCoordinator.shared.showSettings() }
                } else if model.motherLanguageMissing {
                    Button("Open Settings →") { WindowCoordinator.shared.showSettings() }
                }
                Button("Dismiss") { model.errorMessage = nil }
            }
            .buttonStyle(PMLGhostButtonStyle())
        }
        .padding(PMLSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.dangerSoft))
    }

    private var result: some View {
        PMLPanel {
            VStack(alignment: .leading, spacing: PMLSpace.s3) {
                HStack(spacing: PMLSpace.s2) {
                    Text(LocalizedStringKey(resultHeading)).pmlEyebrow()
                    Text(verbatim: draftMeta).font(PMLFont.meta).foregroundStyle(PMLColor.inkMuted).lineLimit(1)
                    Spacer()
                    Button("Regenerate") { Task { await model.send() } }
                        .buttonStyle(PMLSecondaryButtonStyle())
                        .disabled(!model.canSend)
                    Button {
                        model.copyOutput()
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    } label: {
                        Label(LocalizedStringKey(copied ? "Copied!" : "Copy"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(PMLInkButtonStyle())
                }
                Text(model.output)
                    .font(PMLFont.input)
                    .foregroundStyle(PMLColor.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "Sonnet 5 · Medium · 42 words"
    private var draftMeta: String {
        let words = TextCleanup.wordCount(model.output)
        var parts = [ModelLabel.short(model.settings.model)]
        if ModelCatalog.supportsEffort(model.settings.model) { parts.append(ModelLabel.effort(model.settings.effort)) }
        parts.append(words == 1 ? L("1 word") : L("\(words) words"))
        return parts.joined(separator: " · ")
    }

    private var resultHeading: String {
        if model.isAsk { return "Answer" }
        return model.activeMode == "Understand" ? "Explanation" : "Draft"
    }
}

// MARK: - Footer

struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: PMLSpace.s4) {
            Text("Version \(model.appVersion)").foregroundStyle(PMLColor.inkMuted)
            UsageMeterLabel()
            Spacer()
        }
        .font(PMLFont.hint)
        .padding(.horizontal, PMLLayout.windowPadding)
        .padding(.vertical, PMLSpace.s2)
        .background(PMLColor.surface)
    }
}


// MARK: - Shortcut conflict banner

/// Standing warning when the saved shortcut is also used by a common app.
struct ShortcutWarningBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let conflict = model.shortcutAppConflict, !model.shortcutBannerDismissed {
            PMLBanner {
                VStack(alignment: .leading, spacing: PMLSpace.s2) {
                    Label {
                        Text("Your shortcut (\(model.shortcutDisplay)) is known to conflict with \(conflict.app ?? "")'s \(conflict.description) — it may not always reach Per My Last there. Consider choosing a different combo in Settings.")
                            .font(PMLFont.body)
                            .foregroundStyle(PMLColor.ink)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(PMLColor.warning)
                    }
                    HStack(spacing: PMLSpace.s2) {
                        Button("Open Settings →") { WindowCoordinator.shared.showSettings() }
                            .buttonStyle(PMLInkButtonStyle())
                        Button("Dismiss") { model.shortcutBannerDismissed = true }
                            .buttonStyle(PMLGhostButtonStyle())
                    }
                }
            }
        }
    }
}
