import PerMyLastCore
import SwiftUI

extension AppModel {
    var locale: Locale { settings.appLanguage.locale }

    /// The `.lproj` bundle for the language chosen in Settings (independent of
    /// the Mac's own language).
    var languageBundle: Bundle {
        if let path = Bundle.main.path(forResource: settings.appLanguage.resourceName, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}

/// Localizes a string that isn't a SwiftUI `Text` (alerts, messages the model
/// builds) using the app's chosen language.
@MainActor
func L(_ key: String.LocalizationValue) -> String {
    let model = AppModel.shared
    return String(localized: key, bundle: model.languageBundle, locale: model.locale)
}

/// Applies the app language to everything inside, so `Text("…")` picks the
/// right translation as soon as the language changes.
struct LocalizedRoot<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content

    var body: some View {
        content.environment(\.locale, model.locale)
    }
}
