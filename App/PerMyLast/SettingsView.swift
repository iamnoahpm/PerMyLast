import SwiftUI

/// Settings window root: General, Tone Presets, Advanced.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            PresetsSettingsView()
                .tabItem { Label("Tone Presets", systemImage: "rectangle.stack") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(minWidth: 420, minHeight: 520)
    }
}
