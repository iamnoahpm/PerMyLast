import AppKit
import PerMyLastCore
import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tools(wartimeEnabled: $model.settings.wartimePeacetimeEnabled)
                if model.settings.wartimePeacetimeEnabled { WartimePeacetimeCard() }
            }
            .padding(20)
        }
        .onChange(of: model.settings) { model.saveSettings() }
    }

    private func tools(wartimeEnabled: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tools").font(.headline)
            Text("Extra capabilities for Per My Last.").font(.caption).foregroundStyle(.secondary)
            toolRow("✍️", "Write My Way") { Text("Coming soon").badge() }
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
                Text("Wartime / Peacetime Mode").font(.headline)
                Spacer()
                Button(compare ? "Hide the other mode" : "Compare modes") { compare.toggle() }
                    .controlSize(.small)
            }
            Text("This reflects your company's current situation — not a universal standard. Based on your own observation of business pressure, deadlines, and leadership behavior, judge which mode feels closer to reality right now and pick it below. Not sure, or would rather not categorize it? Turn this off from the Tools list above.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Text("Export context for an AI assistant").font(.callout.weight(.semibold))
            ScrollView {
                Text(WartimePeacetime.exportText(for: mode))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 160)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(WartimePeacetime.exportText(for: mode), forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                }
                if copied { Text("Copied.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .cardStyle()
    }

    private var tint: Color { mode == .wartime ? .red : .green }

    private func modeButton(_ value: OperatingMode, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        let selected = mode == value
        return Button { mode = value } label: {
            VStack(spacing: 1) {
                Text(title).fontWeight(selected ? .bold : .regular)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? (value == .wartime ? Color.red : Color.green).opacity(0.16) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func groupView(_ group: OperatingModeGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title).font(.caption.weight(.bold))
            ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.label).font(.caption).foregroundStyle(.secondary)
                    Text(row.value).font(.caption.weight(.medium))
                    if compare, let match = otherProfile.groups.first(where: { $0.title == group.title })?.rows.first(where: { $0.label == row.label }) {
                        Text("\(other.rawValue.capitalized): \(match.value)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
    }
}

private extension Text {
    func badge() -> some View {
        font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
