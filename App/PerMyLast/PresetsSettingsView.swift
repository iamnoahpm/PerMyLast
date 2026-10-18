import PerMyLastCore
import SwiftUI

/// One editable row in the Tone Presets editor. Matched back to the stored
/// preset by `originalLabel`, so renaming a row can't break its identity.
private struct PresetRow: Identifiable, Equatable {
    let id = UUID()
    var originalLabel: String
    var label: String
    var icon: String
    var blurb: String
    var tone: String
    var prompt: String
    var isDefault: Bool
    var uses: Int

    /// The label the preset will have once saved.
    var savedLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? originalLabel : trimmed
    }
}

struct PresetsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var rowsByMode: [String: [PresetRow]] = [:]
    @State private var editingMode = ""
    @State private var status: String?
    @State private var modePendingDelete: String?
    @State private var rowPendingDelete: UUID?

    var body: some View {
        List {
            Section {
                ForEach(model.modes, id: \.self) { mode in
                    TabNameRow(mode: mode, canDelete: model.modes.count > 1,
                               onRename: { newName in
                                   commitEdits()
                                   let ok = model.renameMode(from: mode, to: newName)
                                   if ok { reload() }
                                   return ok
                               },
                               onDelete: { modePendingDelete = mode })
                }
                .onMove { from, to in model.moveModes(from: from, to: to) }
                Button("+ New tab") {
                    commitEdits()
                    model.addMode()
                    reload()
                }
            } header: {
                Text("Tone Preset Tabs")
            } footer: {
                Text("Drag to reorder tabs. Click a tab's name to rename it.")
            }

            Section {
                if model.modes.count > 1 {
                    Picker("Tab", selection: $editingMode) {
                        ForEach(model.modes, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                let rows = rowsByMode[editingMode] ?? []
                if rows.isEmpty {
                    Text("No actions here yet — add one below.").foregroundStyle(.secondary)
                }
                ForEach(bindingRows) { $row in
                    PresetRowEditor(
                        row: $row,
                        canDelete: !row.isDefault && rows.count > 1,
                        onSetDefault: { setDefault(row.id) },
                        onDelete: { rowPendingDelete = row.id })
                }
                .onMove { from, to in rowsByMode[editingMode]?.move(fromOffsets: from, toOffset: to) }
                HStack {
                    Button("+ Add to \(editingMode)") { addPreset() }
                    Spacer()
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    Button("Save Preset Changes") { save() }.buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Drag to reorder. The starred action is the default shown when this tab opens.")
            }
        }
        .onAppear(perform: reload)
        .onChange(of: model.modes) { reload() }
        .confirmationDialog(
            "Delete the \"\(modePendingDelete ?? "")\" tab and all its actions? This can't be undone.",
            isPresented: Binding(get: { modePendingDelete != nil }, set: { if !$0 { modePendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete tab", role: .destructive) {
                if let name = modePendingDelete { model.deleteMode(name); reload() }
                modePendingDelete = nil
            }
        }
        .confirmationDialog(
            "Delete preset \"\(pendingRow?.savedLabel ?? "")\"?",
            isPresented: Binding(get: { rowPendingDelete != nil }, set: { if !$0 { rowPendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete preset", role: .destructive) {
                if let row = pendingRow {
                    commitEdits()
                    model.deletePreset(row.savedLabel)
                    reload()
                }
                rowPendingDelete = nil
            }
        }
    }

    // MARK: Helpers

    private var bindingRows: Binding<[PresetRow]> {
        Binding(get: { rowsByMode[editingMode] ?? [] }, set: { rowsByMode[editingMode] = $0 })
    }

    private var pendingRow: PresetRow? {
        guard let id = rowPendingDelete else { return nil }
        return rowsByMode.values.flatMap { $0 }.first { $0.id == id }
    }

    private func reload() {
        var groups: [String: [PresetRow]] = [:]
        for p in model.presets {
            let category = PresetLibrary.normalizeCategory(p.category, modes: model.modes)
            groups[category, default: []].append(PresetRow(
                originalLabel: p.label, label: p.label, icon: p.icon, blurb: p.blurb,
                tone: p.tone, prompt: p.prompt, isDefault: p.isDefault, uses: p.uses))
        }
        rowsByMode = groups
        if !model.modes.contains(editingMode) { editingMode = model.modes.first ?? "" }
    }

    private func edits() -> [PresetEdit] {
        model.modes.flatMap { rowsByMode[$0] ?? [] }.map {
            PresetEdit(originalLabel: $0.originalLabel, label: $0.label, icon: $0.icon, blurb: $0.blurb,
                       tone: $0.tone, prompt: $0.prompt, isDefault: $0.isDefault)
        }
    }

    /// Applies pending edits before an operation that rebuilds the list, so a
    /// delete or add never throws away what was typed.
    private func commitEdits() {
        guard !rowsByMode.isEmpty else { return }
        model.applyPresetEdits(edits())
        reload()
    }

    private func save() {
        model.applyPresetEdits(edits())
        reload()
        flash("Saved.")
    }

    private func setDefault(_ id: UUID) {
        guard var rows = rowsByMode[editingMode] else { return }
        for i in rows.indices { rows[i].isDefault = rows[i].id == id }
        rowsByMode[editingMode] = rows
    }

    private func addPreset() {
        commitEdits()
        let label = model.addPreset(to: editingMode)
        reload()
        flash("Added \"\(label)\" to \(editingMode) — set its name and prompt, then Save.")
    }

    private func flash(_ message: String) {
        status = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if status == message { status = nil }
        }
    }
}

// MARK: - Rows

private struct TabNameRow: View {
    let mode: String
    let canDelete: Bool
    let onRename: (String) -> Bool
    let onDelete: () -> Void

    @State private var name: String
    @FocusState private var focused: Bool

    init(mode: String, canDelete: Bool, onRename: @escaping (String) -> Bool, onDelete: @escaping () -> Void) {
        self.mode = mode
        self.canDelete = canDelete
        self.onRename = onRename
        self.onDelete = onDelete
        _name = State(initialValue: mode)
    }

    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help("Drag to reorder")
            TextField("Tab name", text: $name)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
                .help("Delete tab")
        }
        .onChange(of: mode) { name = mode }
    }

    private func commit() {
        guard name != mode else { return }
        if !onRename(name) { name = mode }
    }
}

private struct PresetRowEditor: View {
    @Binding var row: PresetRow
    let canDelete: Bool
    let onSetDefault: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help("Drag to reorder")
                TextField("", text: $row.icon)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
                    .help("Icon shown in the main popup — leave blank for none")
                TextField("Name", text: $row.label).fontWeight(.semibold)
                Button(action: onSetDefault) {
                    Label(row.isDefault ? "Default" : "Set default", systemImage: row.isDefault ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .disabled(row.isDefault)
                .help(row.isDefault ? "Shown by default when this tab opens" : "Make this the default for this tab")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(!canDelete)
                    .help(canDelete ? "Delete preset" : "The default action, or the last one in a tab, can't be deleted")
            }
            HStack {
                TextField("Tone (e.g. Direct, Warm)", text: $row.tone).frame(maxWidth: 170)
                TextField("Short description shown under the name", text: $row.blurb)
            }
            TextEditor(text: $row.prompt)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 72)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            Text("used \(row.uses) times").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
