import PerMyLastCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var inputFocused: Bool
    @State private var copied = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tabs(model: $model.activeMode)
                chips
                if model.activeModeTakesIntent {
                    TextField("What do you want to say? (optional)", text: $model.intent)
                        .textFieldStyle(.roundedBorder)
                }
                inputBox(text: $model.inputText)
                sendRow
                resultPanel
            }
            .padding(20)
        }
        .frame(minWidth: 380, minHeight: 460)
        .onChange(of: model.activeMode) { model.selectDefaultPreset() }
        .onChange(of: model.focusToken) { inputFocused = true }
        .onExitCommand { WindowCoordinator.shared.hidePopup() }
    }

    // MARK: Pieces

    private func tabs(model binding: Binding<String>) -> some View {
        HStack {
            Picker("Mode", selection: binding) {
                ForEach(model.modes, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Button { WindowCoordinator.shared.showSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(model.presetsInActiveMode) { preset in
                    let selected = preset.label == model.selectedLabel
                    Button {
                        model.selectedLabel = preset.label
                    } label: {
                        HStack(spacing: 5) {
                            if !preset.icon.isEmpty { Text(preset.icon) }
                            Text(preset.label).fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let preset = model.currentPreset, !preset.blurb.isEmpty {
                Text(model.blurb(for: preset)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func inputBox(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .padding(8)
                if text.wrappedValue.isEmpty {
                    Text("Copy some text, then press ⌘⇧W — or paste it here.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 150)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            let words = text.wrappedValue.split(whereSeparator: \.isWhitespace).count
            if words > 0 { Text("\(words) words").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var sendRow: some View {
        HStack {
            Button {
                Task { await model.send() }
            } label: {
                HStack(spacing: 6) {
                    if model.isSending { ProgressView().controlSize(.small) }
                    Text(model.hasResult ? "Send again" : "Send")
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(model.isSending || model.currentPreset == nil)
            Text("⌘↩").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    @ViewBuilder private var resultPanel: some View {
        if let error = model.errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else if model.hasResult {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(resultTitle).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        model.copyOutput()
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                }
                Text(model.output)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var resultTitle: String {
        guard let preset = model.currentPreset else { return "Result" }
        return preset.tone.isEmpty ? preset.label : "\(preset.label) · \(preset.tone)"
    }
}
