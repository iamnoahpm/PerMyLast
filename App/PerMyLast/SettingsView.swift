import SwiftUI

/// Settings window root: General, Tone Presets, Advanced, plus the footer.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.general

    enum Tab: Hashable { case general, presets, advanced }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                GeneralSettingsView()
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(Tab.general)
                PresetsSettingsView()
                    .tabItem { Label("Tone Presets", systemImage: "rectangle.stack") }
                    .tag(Tab.presets)
                AdvancedSettingsView()
                    .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                    .tag(Tab.advanced)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 520)
        .navigationTitle("Per My Last Settings")
        // One place saves every settings change (the tabs just edit the model).
        .onChange(of: model.settings) { model.saveSettings() }
        .onChange(of: model.writeMyWay) { model.saveWriteMyWay() }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("Version \(model.appVersion)").foregroundStyle(.secondary)
            Button("Send feedback") { model.sendFeedback() }
            Spacer()
            if model.settingsSavedFlash {
                Label("Saved", systemImage: "checkmark").foregroundStyle(.green)
            } else {
                Text("Changes save as you make them").foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .buttonStyle(.link)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
