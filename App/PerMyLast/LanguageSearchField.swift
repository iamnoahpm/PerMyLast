import PerMyLastCore
import SwiftUI

/// Type-to-search language picker (flags included). Free text is accepted too,
/// as in the Electron app.
///
/// At rest it shows "flag name" at the right edge of the row, the same place and
/// shape as the App Language picker next to it. Click it to type and search.
struct LanguageSearchField: View {
    @Binding var selection: String
    @State private var query = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    private var matches: [Language] { Languages.find(query, limit: 6) }
    private var flag: String? { Languages.all.first { $0.name == selection }?.flag }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Mother language") {
                HStack(spacing: 6) {
                    if editing { editor } else { display }
                    // Same slot as the App Language picker's arrows, so both names end at the same x.
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: 29)
                }
            }
            if editing, !query.isEmpty, query != selection, !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches) { language in
                        Button { choose(language.name) } label: {
                            HStack { Text(language.flag); Text(language.name); Spacer() }
                                .padding(.vertical, 4).padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .onChange(of: selection) { if !editing { query = selection } }
    }

    /// "🇫🇷 French", right-aligned, in the same colour as the App Language picker's
    /// value; a click starts editing.
    private var display: some View {
        Button(action: startEditing) {
            HStack(spacing: 6) {
                if let flag { Text(flag) }
                if selection.isEmpty {
                    Text("Type to search — e.g. Spanish, Japanese, French").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: selection).foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mother language")
        .accessibilityValue(selection)
    }

    /// No flag while typing: the field is as wide as the row, so a flag in front of
    /// it would sit far from the text. It comes back with the chosen name.
    private var editor: some View {
        TextField("Mother language", text: $query, prompt: Text("Type to search — e.g. Spanish, Japanese, French"))
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func startEditing() {
        query = selection
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func choose(_ name: String) {
        selection = name
        query = name
        focused = false
        editing = false
    }

    private func commit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != selection { selection = trimmed }
        query = trimmed
        editing = false
    }
}
