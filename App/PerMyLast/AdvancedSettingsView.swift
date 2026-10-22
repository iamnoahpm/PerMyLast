import AppKit
import PerMyLastCore
import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tools(wartimeEnabled: $model.settings.wartimePeacetimeEnabled, writeMyWayEnabled: $model.writeMyWay.enabled)
                if model.writeMyWay.enabled { WriteMyWayCard() }
                if model.settings.wartimePeacetimeEnabled { WartimePeacetimeCard() }
            }
            .padding(20)
        }
    }

    private func tools(wartimeEnabled: Binding<Bool>, writeMyWayEnabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tools").font(PMLFont.cardTitle)
            Text("Extra capabilities for Per My Last.").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            toolRow("✍️", "Write My Way") { Toggle("", isOn: writeMyWayEnabled).labelsHidden().toggleStyle(.switch) }
            toolRow("⭐", "VIP Contacts") { Text("Coming soon").badge() }
            toolRow("⚔️", "Wartime / Peacetime Mode") { Toggle("", isOn: wartimeEnabled).labelsHidden().toggleStyle(.switch) }
        }
        .cardStyle()
    }

    private func toolRow<Trailing: View>(_ icon: String, _ name: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(icon)
            Text(name)
            Spacer()
            trailing()
        }
        .padding(.vertical, 2)
    }
}

/// Wartime / Peacetime configurator: pick the mode that matches the company's
/// current situation, compare the two, and copy the context for an AI assistant.
private struct WartimePeacetimeCard: View {
    @State private var mode = OperatingMode.wartime
    @State private var compare = false
    @State private var copied = false

    private var other: OperatingMode { mode == .wartime ? .peacetime : .wartime }
    private var profile: OperatingModeProfile { WartimePeacetime.profile(for: mode) }
    private var otherProfile: OperatingModeProfile { WartimePeacetime.profile(for: other) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wartime / Peacetime Mode").font(PMLFont.cardTitle)
                Spacer()
                Button(LocalizedStringKey(compare ? "Hide the other mode" : "Compare modes")) { compare.toggle() }
                    .controlSize(.small)
            }
            Text("This reflects your company's current situation — not a universal standard. Based on your own observation of business pressure, deadlines, and leadership behavior, judge which mode feels closer to reality right now and pick it below. Not sure, or would rather not categorize it? Turn this off from the Tools list above.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)

            HStack(spacing: 6) {
                modeButton(.wartime, "Wartime", "Speed over sustainability")
                modeButton(.peacetime, "Peacetime", "Sustainability over speed")
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(Array(profile.groups.enumerated()), id: \.offset) { _, group in
                    groupView(group)
                }
            }

            Text(profile.why)
                .font(PMLFont.body.italic())
                .foregroundStyle(PMLColor.inkMuted)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tintSoft, in: RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous))

            Text("Export context for an AI assistant").font(PMLFont.select.weight(.bold))
            ScrollView {
                Text(WartimePeacetime.exportText(for: mode))
                    .font(PMLFont.kbd)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 160)
            .background(PMLColor.surfaceSunken, in: RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(WartimePeacetime.exportText(for: mode), forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                }
                if copied { Text("Copied.").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted) }
            }
        }
        .cardStyle()
    }

    private var tint: Color { mode == .wartime ? PMLColor.danger : PMLColor.success }
    private var tintSoft: Color { mode == .wartime ? PMLColor.dangerSoft : PMLColor.successSoft }

    private func modeButton(_ value: OperatingMode, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        let selected = mode == value
        return Button { mode = value } label: {
            VStack(spacing: 1) {
                Text(title).fontWeight(selected ? .bold : .regular)
                Text(subtitle).font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? (value == .wartime ? PMLColor.danger : PMLColor.success) : PMLColor.ink)
            .background(selected ? (value == .wartime ? PMLColor.dangerSoft : PMLColor.successSoft) : PMLColor.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func groupView(_ group: OperatingModeGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title).font(PMLFont.hint.weight(.bold))
            ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.label).font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                    Text(row.value).font(PMLFont.hint.weight(.medium))
                    if compare, let match = otherProfile.groups.first(where: { $0.title == group.title })?.rows.first(where: { $0.label == row.label }) {
                        Text(verbatim: "\(other.rawValue.capitalized): \(match.value)").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PMLColor.surfaceInset, in: RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous))
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PMLColor.surface, in: RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous).strokeBorder(PMLColor.line))
    }
}

private extension Text {
    func badge() -> some View {
        font(PMLFont.badge).tracking(0.42).textCase(.uppercase)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(PMLColor.surfaceSunken, in: Capsule())
            .foregroundStyle(PMLColor.inkMuted)
    }
}


/// Write My Way: how you write (English level, tone, length, format). A preview
/// like the Electron one: choices are remembered but not yet sent with rewrites.
private struct WriteMyWayCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            Text("Write My Way").font(PMLFont.cardTitle)
            Text("Choose how you write. Actions with \"Use my Write My Way settings\" turned on (Like Brit. and Like Me by default) follow these choices, so rewrites already sound like you.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)

            englishLevel(settings: $model.writeMyWay)
            Divider()
            writingStyle(settings: $model.writeMyWay)
            Divider()
            comingSoon("Target Audience", "Who this writing should land with — beginners, experts, children, and so on. Set per Tone Preset, not here.")
            comingSoon("Custom Instructions", "Standing rules the AI should always follow when writing. Set per Tone Preset, not here.")
        }
        .cardStyle()
    }

    private func englishLevel(settings: Binding<WriteMyWaySettings>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("English Level").fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: settings.englishLevelEnabled).labelsHidden().toggleStyle(.switch)
            }
            Text("Off by default. When on, pick the test you know your level from and enter your score — a recent actual score or your own best estimate.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            if settings.wrappedValue.englishLevelEnabled {
                Picker("Test", selection: settings.testType) {
                    ForEach(["TOEIC", "IELTS", "SAT", "CEFR", "TOEFL"], id: \.self) { Text($0).tag($0) }
                }
                TextField("Score", text: settings.testScore, prompt: Text("e.g. 850, 7.0, 1350, B2, 100"))
            }
        }
    }

    private func writingStyle(settings: Binding<WriteMyWaySettings>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Writing Style").fontWeight(.semibold)
            Text("The default tone, length, and format Per My Last aims for.")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)

            Picker("Tone", selection: settings.tone) {
                Text("Professional").tag("professional")
                Text("Casual").tag("casual")
                Text("Friendly").tag("friendly")
                Text("Persuasive").tag("persuasive")
                Text("Other…").tag("other")
            }
            if settings.wrappedValue.tone == "other" {
                TextField("Custom tone", text: settings.customTone, prompt: Text("Describe the tone you want"))
            }

            Picker("Length", selection: settings.length) {
                Text("Short").tag("short")
                Text("Medium").tag("medium")
                Text("Long").tag("long")
                Text("Custom").tag("custom")
            }
            .pickerStyle(.segmented)
            if settings.wrappedValue.length == "custom" {
                HStack {
                    TextField("Max amount", text: settings.customLength, prompt: Text("Max amount"))
                    Picker("Unit", selection: settings.customLengthUnit) {
                        Text("Words").tag("words")
                        Text("Characters").tag("characters")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 130)
                }
            }

            Picker("Format", selection: settings.format) {
                Text("Bullet points").tag("bullets")
                Text("Message (Teams / Slack)").tag("message")
                Text("Email").tag("email")
                Text("Essay").tag("essay")
                Text("Blog post").tag("blog")
            }
        }
    }

    private func comingSoon(_ title: LocalizedStringKey, _ hint: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).fontWeight(.semibold)
                Text("— coming soon").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            }
            Text(hint).font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
        }
        .opacity(0.7)
    }
}
