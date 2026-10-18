import PerMyLastCore
import SwiftUI

/// Settings → Tone Presets, as pick-then-edit:
/// tabs along the top, that tab's actions on the left, the chosen action's
/// editor on the right. Edits save as you make them.
struct PresetsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = ""
    @State private var selected: String?
    @State private var showTabManager = false

    private var actions: [Preset] {
        model.presets.filter { PresetLibrary.normalizeCategory($0.category, modes: model.modes) == mode }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 220)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if mode.isEmpty { mode = model.modes.first ?? "" }; ensureSelection() }
        .onChange(of: mode) { ensureSelection() }
        .onChange(of: model.modes) {
            if !model.modes.contains(mode) { mode = model.modes.first ?? "" }
        }
        .onChange(of: actions.map(\.label)) { ensureSelection() }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 10) {
            Picker("Tab", selection: $mode) {
                ForEach(model.modes, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Button("Edit tabs…") { showTabManager = true }
                .popover(isPresented: $showTabManager, arrowEdge: .bottom) { TabManager() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Actions list

    private var sidebar: some View {
        VStack(spacing: 0) {
            if actions.isEmpty {
                Spacer()
                Text("No actions here yet — add one below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List(selection: $selected) {
                    ForEach(actions) { preset in
                        ActionRow(preset: preset).tag(preset.label)
                    }
                    .onMove { from, to in model.reorderActions(in: mode, from: from, to: to) }
                }
                .listStyle(.sidebar)
            }
            Divider()
            Button {
                selected = model.addPreset(to: mode)
            } label: {
                Text("+ Add to \(mode)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    // MARK: Editor

    @ViewBuilder private var detail: some View {
        if let selected, actions.contains(where: { $0.label == selected }) {
            ActionEditor(label: selected, mode: mode, onRenamed: { self.selected = $0 }, onDeleted: { self.selected = nil })
        } else {
            Text("Select an action to edit it.")
                .foregroundStyle(.secondary)
        }
    }

    private func ensureSelection() {
        guard !mode.isEmpty else { return }
        if let selected, actions.contains(where: { $0.label == selected }) { return }
        selected = (actions.first(where: \.isDefault) ?? actions.first)?.label
    }
}

private struct ActionRow: View {
    let preset: Preset

    var body: some View {
        HStack(spacing: 8) {
            Text(preset.icon.isEmpty ? "•" : preset.icon)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.label).fontWeight(.medium).lineLimit(1)
                if !preset.blurb.isEmpty {
                    Text(preset.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if preset.isDefault {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.accentColor).help("Default")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Editor for one action

private struct Draft: Equatable {
    var icon = "", label = "", blurb = "", tone = "", prompt = ""
    var usesWriteMyWay = false, matchesEnglishLevel = false

    init() {}
    init(_ p: Preset) {
        icon = p.icon; label = p.label; blurb = p.blurb; tone = p.tone; prompt = p.prompt
        usesWriteMyWay = p.usesWriteMyWay; matchesEnglishLevel = p.matchesEnglishLevel
    }
}

private struct ActionEditor: View {
    @Environment(AppModel.self) private var model
    /// The saved label of the action being edited.
    let label: String
    let mode: String
    let onRenamed: (String) -> Void
    let onDeleted: () -> Void

    @State private var draft = Draft()
    @State private var originalLabel = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    private var preset: Preset? { model.presets.first { $0.label == originalLabel } }
    private var trimmedName: String { draft.label.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameTaken: Bool { model.presetLabelTaken(trimmedName, except: originalLabel) }
    private var promptBlank: Bool { draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isEdited: Bool { preset.map { draft.prompt != $0.originalPrompt } ?? false }

    var body: some View {
        ScrollView {
            if let preset {
                VStack(alignment: .leading, spacing: 18) {
                    identity
                    promptSection(preset)
                    writeMyWaySection
                    footer(preset)
                }
                .padding(20)
            }
        }
        .onAppear { load(label); if draft.prompt.isEmpty { nameFocused = true } }
        .onChange(of: label) { flush(); load(label) }
        .onChange(of: draft) { scheduleSave() }
        .onDisappear { flush() }
        .confirmationDialog(
            "Delete preset \"\(preset?.label ?? "")\"?",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete preset", role: .destructive) {
                if let preset { model.deletePreset(preset.label) }
                onDeleted()
            }
        }
    }

    // MARK: Sections

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                field("Icon") {
                    TextField("", text: $draft.icon)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .help("Icon shown in the main popup — leave blank for none")
                }
                field("Name") {
                    TextField("Name", text: $draft.label)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                }
            }
            if nameTaken {
                Text("Name already used").font(.caption).foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 10) {
                field("Tone") {
                    TextField("Tone (e.g. Direct, Warm)", text: $draft.tone)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
                field("Description") {
                    TextField("Short description shown under the name", text: $draft.blurb)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func promptSection(_ preset: Preset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Prompt").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if isEdited {
                    Text("Edited")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
                Spacer()
                if isEdited {
                    Button("Reset to original") { draft.prompt = preset.originalPrompt }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            TextEditor(text: $draft.prompt)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 150)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))
            if promptBlank {
                Text("A prompt is needed. The previous one stays until you write a new one.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var writeMyWaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Write My Way").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use my Write My Way settings", isOn: $draft.usesWriteMyWay)
                Text("Adds your tone, length and format from Advanced → Write My Way.")
                    .font(.caption).foregroundStyle(.secondary)
                if draft.usesWriteMyWay {
                    Toggle("Match my English level", isOn: $draft.matchesEnglishLevel)
                        .padding(.leading, 20)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func footer(_ preset: Preset) -> some View {
        let onlyOne = model.presets.filter {
            PresetLibrary.normalizeCategory($0.category, modes: model.modes) == mode
        }.count <= 1
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                if preset.isDefault {
                    Label("Default for \(mode)", systemImage: "star.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Button { model.setDefaultPreset(preset.label) } label: {
                        Label("Set as default for \(mode)", systemImage: "star")
                    }
                }
                Spacer()
                Button("Delete action", role: .destructive) { confirmDelete = true }
                    .disabled(preset.isDefault || onlyOne)
                    .help("The default action, or the last one in a tab, can't be deleted")
            }
            Text("used \(preset.uses) times").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func field<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Saving (live, a moment after you stop typing)

    private func load(_ saved: String) {
        originalLabel = saved
        if let p = model.presets.first(where: { $0.label == saved }) { draft = Draft(p) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.5))
            if !Task.isCancelled { commit() }
        }
    }

    private func flush() {
        saveTask?.cancel()
        commit()
    }

    private func commit() {
        guard let preset, draft != Draft(preset) else { return }
        guard !trimmedName.isEmpty, !nameTaken else { return }
        // A blank prompt isn't saved (the stored one is kept), but the rest of the edit is.
        let prompt = promptBlank ? preset.prompt : draft.prompt
        model.updatePreset(originalLabel: originalLabel, edit: PresetEdit(
            originalLabel: originalLabel, label: trimmedName, icon: draft.icon, blurb: draft.blurb,
            tone: draft.tone, prompt: prompt, isDefault: preset.isDefault,
            usesWriteMyWay: draft.usesWriteMyWay,
            matchesEnglishLevel: draft.usesWriteMyWay ? draft.matchesEnglishLevel : false))
        let renamed = trimmedName != originalLabel
        originalLabel = trimmedName
        if renamed { onRenamed(trimmedName) }
    }
}

// MARK: - Tab manager (popover)

private struct TabManager: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tone Preset Tabs").font(.headline)
            List {
                ForEach(model.modes, id: \.self) { mode in
                    TabNameRow(mode: mode, canDelete: model.modes.count > 1,
                               onRename: { model.renameMode(from: mode, to: $0) },
                               onDelete: { pendingDelete = mode })
                }
                .onMove { from, to in model.moveModes(from: from, to: to) }
            }
            .frame(height: min(CGFloat(model.modes.count) * 30 + 12, 240))
            HStack {
                Button("+ New tab") { model.addMode() }
                Spacer()
            }
            Text("Drag to reorder tabs. Click a tab's name to rename it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
        .confirmationDialog(
            "Delete the \"\(pendingDelete ?? "")\" tab and all its actions? This can't be undone.",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete tab", role: .destructive) {
                if let name = pendingDelete { model.deleteMode(name) }
                pendingDelete = nil
            }
        }
    }
}

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
