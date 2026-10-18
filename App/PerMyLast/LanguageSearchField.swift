import PerMyLastCore
import SwiftUI

/// Type-to-search language picker (flags included). Free text is accepted too,
/// as in the Electron app.
struct LanguageSearchField: View {
    @Binding var selection: String
    @State private var query = ""
    @FocusState private var focused: Bool

    private var matches: [Language] { Languages.find(query, limit: 6) }
    private var flag: String? { Languages.all.first { $0.name == selection }?.flag }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let flag { Text(flag) }
                TextField("Mother language", text: $query, prompt: Text("Type to search — e.g. Spanish, Japanese, French"))
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            }
            if focused, !query.isEmpty, query != selection, !matches.isEmpty {
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
        .onAppear { query = selection }
        .onChange(of: selection) { if !focused { query = selection } }
    }

    private func choose(_ name: String) {
        selection = name
        query = name
        focused = false
    }

    private func commit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != selection { selection = trimmed }
        query = trimmed
    }
}
