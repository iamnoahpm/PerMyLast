import SwiftUI

/// The strip under a finished result, in two steps: a one-tap rating, then a plain-language ask to share the run.
struct FeedbackPrompt: View {
    @Environment(AppModel.self) private var app
    private var feedback: FeedbackModel { .shared }

    var body: some View {
        Group {
            switch feedback.stage {
            case .hidden:
                EmptyView()
            case .rating:
                ratingBar
            case .consent:
                FeedbackConsentCard()
            case .thanks(let shared):
                card { Text(LocalizedStringKey(shared ? "Thank you. That helps." : "Thanks for letting us know.")).font(PMLFont.body).foregroundStyle(PMLColor.inkSoft); Spacer(minLength: 0) }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(PMLMotion.base, value: feedback.stage)
    }

    private var ratingBar: some View {
        card {
            Text("How did that go?").font(PMLFont.body).foregroundStyle(PMLColor.ink).lineLimit(1)
            Spacer(minLength: PMLSpace.s2)
            ForEach(FeedbackModel.Rating.allCases, id: \.self) { rating in
                Button(LocalizedStringKey(rating.label)) { feedback.rate(rating) }
                    .buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkMuted))
            }
            Button { feedback.dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkMuted))
                .help("Don't ask for a while")
                .accessibilityLabel("Dismiss")
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: PMLSpace.s1) { content() }
            .padding(.horizontal, PMLSpace.s3)
            .padding(.vertical, PMLSpace.s1)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.surface))
            .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(PMLColor.line, lineWidth: 1))
    }
}

extension FeedbackModel.Rating {
    var label: String {
        switch self { case .bad: "Bad"; case .fine: "Fine"; case .good: "Good" }
    }
}

/// Step two. Says what would be sent and what would not, shows the exact payload as a log the person can edit or empty, and
/// defaults to "No thanks".
private struct FeedbackConsentCard: View {
    @State private var showPreview = false
    @Bindable private var feedback = FeedbackModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s3) {
            VStack(alignment: .leading, spacing: PMLSpace.s1) {
                Text("Thanks. Can we see this run to make Per My Last better?").font(PMLFont.cardTitle).foregroundStyle(PMLColor.ink)
                Text("It is anonymous: nothing links it to your name, email, account or API key, and screenshots are never sent. Because of that, we can't find it later to delete it.")
                    .font(PMLFont.body).foregroundStyle(PMLColor.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                line("We would receive:", items: "the prompt, the text you gave, the result, your rating")
                line("And these settings:", items: "model, effort, mode and preset, app and macOS version, app language")
            }
            // The whole row toggles, not just the caret.
            Button { withAnimation(PMLMotion.fast) { showPreview.toggle() } } label: {
                HStack(spacing: PMLSpace.s1) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(showPreview ? 90 : 0))
                    Text("Review, edit or remove what's sent").font(PMLFont.select)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(PMLColor.accentText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            if showPreview { log }
            Text(LocalizedStringKey(showPreview ? "Edit any value above, or press Remove to leave it out. Only what you see here is sent." : "If it contains anything private, review it first or choose No thanks."))
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            HStack(spacing: PMLSpace.s2) {
                Button("Share this run") { feedback.share() }
                    .buttonStyle(PMLPrimaryButtonStyle(size: .compact))
                    .disabled(feedback.isSending)
                Button("No thanks") { feedback.decline() }
                    .buttonStyle(PMLSecondaryButtonStyle())
                Spacer(minLength: 0)
                Button("Don't ask again") { feedback.neverAskAgain() }
                    .buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkMuted))
            }
        }
        .padding(PMLSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).fill(PMLColor.surface))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(PMLColor.line, lineWidth: 1))
    }

    private func line(_ title: LocalizedStringKey, items: LocalizedStringKey) -> some View {
        (Text(title).fontWeight(.semibold) + Text(" ") + Text(items))
            .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted).fixedSize(horizontal: false, vertical: true)
    }

    /// The payload as a log: `key: value` lines, then the three texts as editable fields. Keys are the real field names, untranslated.
    @ViewBuilder private var log: some View {
        if case .consent(let rating) = feedback.stage {
            VStack(alignment: .leading, spacing: PMLSpace.s2) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(feedback.settingsLog(for: rating), id: \.key) { entry in
                        Text(verbatim: "\(entry.key): \(entry.value)")
                    }
                }
                .font(PMLFont.log).foregroundStyle(PMLColor.inkSoft).textSelection(.enabled)
                field("prompt", text: $feedback.draftPrompt)
                field("input", text: $feedback.draftInput)
                field("output", text: $feedback.draftOutput)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PMLSpace.s2)
            .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).fill(PMLColor.surfaceInset))
        }
    }

    private func field(_ key: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "\(key):").font(PMLFont.log).foregroundStyle(PMLColor.inkSoft)
                Spacer(minLength: 0)
                Button("Remove") { text.wrappedValue = "" }
                    .buttonStyle(PMLGhostButtonStyle(tint: PMLColor.inkMuted))
                    .disabled(text.wrappedValue.isEmpty)
            }
            TextEditor(text: text)
                .font(PMLFont.log).foregroundStyle(PMLColor.ink)
                .scrollContentBackground(.hidden)
                .padding(PMLSpace.s1)
                .frame(minHeight: 44, maxHeight: 110)
                .background(RoundedRectangle(cornerRadius: PMLRadius.badge, style: .continuous).fill(PMLColor.surface))
                .overlay(RoundedRectangle(cornerRadius: PMLRadius.badge, style: .continuous).strokeBorder(PMLColor.line, lineWidth: 1))
        }
    }
}
