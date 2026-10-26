import AppKit
import AudioToolbox
import AVFoundation
import CoreAudio
import PerMyLastCore
import Speech
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Images

/// A screenshot attached to the Reply composer, already downscaled and encoded for the API.
struct AttachedImage: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let mediaType: String
    let thumbnail: NSImage

    static func == (a: AttachedImage, b: AttachedImage) -> Bool { a.id == b.id }

    /// The longest side the model reads at full detail; larger pictures only cost upload time.
    private static let maxSide: CGFloat = 1568
    private static let maxBytes = 4_000_000

    static func make(from image: NSImage) -> AttachedImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        let rep: NSBitmapImageRep
        if scale < 1 {
            guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(origin: .zero, size: size))
            guard let scaled = ctx.makeImage() else { return nil }
            rep = NSBitmapImageRep(cgImage: scaled)
        } else {
            rep = NSBitmapImageRep(cgImage: cg)
        }
        if let png = rep.representation(using: .png, properties: [:]), png.count <= maxBytes {
            return AttachedImage(data: png, mediaType: "image/png", thumbnail: image)
        }
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return AttachedImage(data: jpeg, mediaType: "image/jpeg", thumbnail: image)
    }

    static func make(fileURL: URL) -> AttachedImage? {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        guard let image = NSImage(contentsOf: fileURL) else { return nil }
        return make(from: image)
    }

    /// Images on the clipboard, when pasting should attach them instead of inserting text:
    /// image files copied in Finder, or a screenshot with no text beside it.
    @MainActor static func fromPasteboard(_ pb: NSPasteboard = .general) -> [AttachedImage]? {
        let urlOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingContentsConformToTypes: [UTType.image.identifier]]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: urlOptions) as? [URL], !urls.isEmpty {
            let images = urls.compactMap { make(fileURL: $0) }
            if !images.isEmpty { return images }
        }
        guard pb.string(forType: .string) == nil,
              let raw = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage], !raw.isEmpty else { return nil }
        let images = raw.compactMap { make(from: $0) }
        return images.isEmpty ? nil : images
    }
}

// MARK: - Dictation

/// What dictation listens for. The recognizer takes one language per run, so Mixed runs two
/// (your mother language and English) on the same audio and keeps the more confident words.
/// Mixed comes first and is the default: it is the one that suits most people.
enum DictationChoice: String, CaseIterable {
    case mixed, mother, english

    var needsMotherLanguage: Bool { self != .english }
}

/// On-device dictation into the focused field. One tap starts it, the next stops it.
@MainActor @Observable
final class DictationController {
    var isListening = false
    /// Shown inline under the toolbar; nil when all is well.
    var error: String?
    var errorOpensSettings: URL?
    /// 0...1 loudness of the microphone while listening, for the level bar.
    var level: Float = 0
    /// True while the first-use language tips are on screen.
    var showSetup = false
    var choice = DictationChoice(rawValue: UserDefaults.standard.string(forKey: "dictationChoice") ?? "") ?? .mixed {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "dictationChoice") }
    }
    /// "en-GB" or "en-US": the English used alone, and beside your mother language in Mixed.
    var englishVariant = UserDefaults.standard.string(forKey: "dictationEnglish")
        ?? (Locale.current.region?.identifier == "GB" ? "en-GB" : "en-US") {
        didSet { UserDefaults.standard.set(englishVariant, forKey: "dictationEnglish") }
    }
    /// Unique ID of the chosen input device; empty follows the system default.
    var deviceUID = UserDefaults.standard.string(forKey: "dictationDevice") ?? "" {
        didSet { UserDefaults.standard.set(deviceUID, forKey: "dictationDevice") }
    }
    private(set) var setupDone = UserDefaults.standard.bool(forKey: "dictationSetupDone")

    struct Input: Identifiable, Equatable { let id: String; let name: String }

    static func inputs() -> [Input] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { Input(id: $0.uniqueID, name: $0.localizedName) }
    }

    static var defaultInputName: String { AVCaptureDevice.default(for: .audio)?.localizedName ?? "" }

    /// One locale per recognizer run: the mother language first, so it wins ties.
    func locales(motherLanguage: String) -> [Locale] {
        switch choice {
        case .english: [Locale(identifier: englishVariant)]
        case .mother: [DictationLocales.locale(forName: motherLanguage)]
        case .mixed: [DictationLocales.locale(forName: motherLanguage), Locale(identifier: englishVariant)]
        }
    }

    // MARK: Session

    private struct Seg: Sendable {
        let text: String, start: TimeInterval, duration: TimeInterval, confidence: Float
    }

    private struct Run {
        let request: SFSpeechAudioBufferRecognitionRequest
        var task: SFSpeechRecognitionTask?
        var text = ""
        var segments: [Seg] = []
        var isFinal = false
    }

    private var runs: [Run] = []
    private var base = ""
    private var onText: ((String) -> Void)?
    private var motherLanguage = ""
    private let engine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var pending: (base: String, motherLanguage: String, onText: (String) -> Void)?
    /// Stop after this long without new words.
    private let silenceTimeout: TimeInterval = 8

    func toggle(base: String, motherLanguage: String, onText: @escaping (String) -> Void) {
        if isListening { stop() } else { Task { await start(base: base, motherLanguage: motherLanguage, onText: onText) } }
    }

    /// The setup popover's button: remember that the tips were seen, then begin the dictation that asked for them.
    func completeSetup() {
        UserDefaults.standard.set(true, forKey: "dictationSetupDone")
        setupDone = true
        showSetup = false
        guard let p = pending else { return }
        pending = nil
        Task { await start(base: p.base, motherLanguage: p.motherLanguage, onText: p.onText) }
    }

    private func start(base: String, motherLanguage: String, onText: @escaping (String) -> Void) async {
        error = nil
        errorOpensSettings = nil
        guard await SpeechAuth.speechAllowed() else {
            fail("Error: Speech recognition is off. Turn it on in System Settings.", pane: "Privacy_SpeechRecognition"); return
        }
        guard await SpeechAuth.microphoneAllowed() else {
            fail("Error: Microphone access is off. Turn it on in System Settings.", pane: "Privacy_Microphone"); return
        }
        // Right after permission: explain which language to pick, and ask for a mother language if there is none.
        if !setupDone || (choice.needsMotherLanguage && motherLanguage.trimmingCharacters(in: .whitespaces).isEmpty) {
            pending = (base, motherLanguage, onText)
            showSetup = true
            return
        }

        var started: [Run] = []
        var recognizers: [SFSpeechRecognizer] = []
        for locale in locales(motherLanguage: motherLanguage) {
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
                fail("Error: Dictation isn't available for your language right now. Try again later.", pane: nil); return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            started.append(Run(request: request))
            recognizers.append(recognizer)
        }
        runs = started
        self.base = base
        self.onText = onText
        self.motherLanguage = motherLanguage

        let input = engine.inputNode
        if !deviceUID.isEmpty { Self.useDevice(uid: deviceUID, on: input) }
        Self.installTap(on: input, requests: started.map(\.request)) { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        engine.prepare()
        do { try engine.start() } catch {
            engine.inputNode.removeTap(onBus: 0)
            runs = []
            fail("Error: Couldn't start the microphone. Check your input device.", pane: nil); return
        }
        isListening = true
        armSilenceTimer()

        for (index, recognizer) in recognizers.enumerated() {
            runs[index].task = recognizer.recognitionTask(with: runs[index].request) { [weak self] result, err in
                let text = result?.bestTranscription.formattedString ?? ""
                let segs = result?.bestTranscription.segments.map {
                    Seg(text: $0.substring, start: $0.timestamp, duration: $0.duration, confidence: $0.confidence)
                } ?? []
                let done = (result?.isFinal ?? false) || err != nil
                Task { @MainActor in self?.handle(index: index, text: text, segments: segs, done: done) }
            }
        }
    }

    private func handle(index: Int, text: String, segments: [Seg], done: Bool) {
        guard runs.indices.contains(index) else { return }
        if !text.isEmpty { runs[index].text = text; runs[index].segments = segments }
        if done { runs[index].isFinal = true }
        // Live text comes from the first recognizer; Mixed settles on the best words once you stop.
        if index == 0, isListening, !text.isEmpty {
            onText?(joined(text))
            armSilenceTimer()
        }
        if done, isListening, runs.count == 1 { stop() }
    }

    func stop() {
        guard isListening else { return }
        silenceTimer?.invalidate(); silenceTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        level = 0
        isListening = false
        for run in runs { run.request.endAudio() }
        Task { await settle() }
    }

    /// Waits briefly for the recognizers' last words, then writes the final text.
    private func settle() async {
        for _ in 0..<20 where !runs.allSatisfy(\.isFinal) { try? await Task.sleep(for: .milliseconds(100)) }
        let text = runs.count > 1 ? mergedText() : (runs.first?.text ?? "")
        if !text.isEmpty { onText?(joined(text)) }
        for run in runs { run.task?.cancel() }
        runs = []
        onText = nil
    }

    private func joined(_ text: String) -> String {
        let separator = base.isEmpty || base.hasSuffix(" ") || base.hasSuffix("\n") ? "" : " "
        return base + separator + text
    }

    /// Walks both transcripts in time order; where two words cover the same moment, the more confident one wins.
    private func mergedText() -> String {
        let all = runs.enumerated().flatMap { index, run in run.segments.map { (seg: $0, run: index) } }
            .sorted { ($0.seg.start, $0.run) < ($1.seg.start, $1.run) }
        var chosen: [Seg] = []
        for item in all {
            if let last = chosen.last, item.seg.start < last.start + last.duration * 0.6 {
                if item.seg.confidence > last.confidence { chosen[chosen.count - 1] = item.seg }
            } else {
                chosen.append(item.seg)
            }
        }
        return chosen.map(\.text).joined(separator: " ")
    }

    /// The tap runs on the audio thread, so it must not inherit this class's main-actor isolation.
    private nonisolated static func installTap(on node: AVAudioInputNode, requests: [SFSpeechAudioBufferRecognitionRequest],
                                               onLevel: @escaping @Sendable (Float) -> Void) {
        nonisolated(unsafe) let requests = requests
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in
            for request in requests { request.append(buffer) }
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            onLevel(min(1, rms * 8))
        }
    }

    /// Points the engine's input at a specific microphone instead of the system default.
    private nonisolated static func useDevice(uid: String, on node: AVAudioInputNode) {
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &deviceID)
        }
        guard status == noErr, deviceID != 0, let unit = node.audioUnit else { return }
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    private func fail(_ message: String.LocalizationValue, pane: String?) {
        error = L(message)
        errorOpensSettings = pane.flatMap { URL(string: "x-apple.systempreferences:com.apple.preference.security?\($0)") }
    }
}

private enum SpeechAuth {
    static func speechAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        default: return false
        }
    }

    static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

/// Language helpers for dictation.
enum DictationLocales {
    /// "vi" for Vietnamese, from the language's English name.
    static func code(forName name: String) -> String? {
        let en = Locale(identifier: "en")
        return Locale.LanguageCode.isoLanguageCodes.map(\.identifier).first { en.localizedString(forLanguageCode: $0) == name }
    }

    /// A locale the recognizer supports for this language name, preferring your region.
    static func locale(forName name: String) -> Locale {
        let code = code(forName: name) ?? Locale.current.language.languageCode?.identifier
        let all = SFSpeechRecognizer.supportedLocales().filter { $0.language.languageCode?.identifier == code }
        return all.first { $0.region == Locale.current.region } ?? all.first ?? Locale(identifier: "en-US")
    }

    static func englishName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

// MARK: - Model labels

/// Short names for the model picker. The ids come from `ModelCatalog`.
@MainActor
enum ModelLabel {
    static func short(_ id: String) -> String {
        switch id {
        case "claude-sonnet-5": "Sonnet 5"
        case "claude-opus-5": "Opus 5"
        case "claude-haiku-4-5": "Haiku 4.5"
        case "claude-fable-5": "Fable 5"
        default: id.replacingOccurrences(of: "claude-", with: "")
        }
    }

    static func tagline(_ id: String) -> LocalizedStringKey {
        switch id {
        case "claude-sonnet-5": "Balanced"
        case "claude-opus-5": "Most capable"
        case "claude-haiku-4-5": "Fastest"
        case "claude-fable-5": "Frontier"
        default: ""
        }
    }

    static func effort(_ e: Effort) -> String {
        switch e {
        case .low: L("Low")
        case .medium: L("Medium")
        case .high: L("High")
        case .xhigh: L("Extra high")
        case .max: L("Max")
        }
    }
}

// MARK: - Composer

/// Reply: their message and your intent in one box. "They said" on top, "You want to say" below on the accent wash,
/// with the intent's own toolbar (screenshot, dictate, view prompt, model, Send).
struct ReplyComposer: View {
    @Environment(AppModel.self) private var model
    var theirFocus: FocusState<Bool>.Binding
    var intentFocus: FocusState<Bool>.Binding

    private enum Section { case theirs, intent }

    @State private var dictation = DictationController()
    @State private var focused: Section?
    @State private var pasteMonitor: Any?
    @State private var dropTarget: Section?

    private var anyFocus: Bool { focused != nil }

    var body: some View {
        VStack(spacing: 0) {
            theirSection
            Rectangle().fill(PMLColor.divider).frame(height: 1)
            intentSection
        }
        .background(PMLColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous)
            .strokeBorder(PMLColor.line, lineWidth: 1))
        .onChange(of: theirFocus.wrappedValue) { _, on in focusChanged(.theirs, on) }
        .onChange(of: intentFocus.wrappedValue) { _, on in focusChanged(.intent, on) }
        .onChange(of: model.inputText) { old, new in
            // A paste lands as one big jump in length; run it through the same clean-up as captured text.
            if new.count - old.count > 20 { model.inputText = TextCleanup.beautify(new) }
        }
        .onAppear(perform: installPasteMonitor)
        .onDisappear { removePasteMonitor(); dictation.stop() }
    }

    private func focusChanged(_ section: Section, _ on: Bool) {
        if on { focused = section }
        else if focused == section { focused = nil }
    }

    // MARK: They said

    private var theirSection: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("They said").pmlEyebrow(PMLColor.inkMuted)
                Spacer()
                if !model.theirImages.isEmpty {
                    Text(verbatim: model.theirImages.count == 1 ? L("1 image") : L("\(model.theirImages.count) images"))
                        .font(PMLFont.meta).foregroundStyle(PMLColor.inkMuted)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14)
            ComposerTextArea(
                text: $model.inputText,
                placeholder: L("Select some text, then press \(model.shortcutDisplay), or paste text or a screenshot here."),
                minHeight: 130, maxHeight: 200, focus: theirFocus)
            if !model.theirImages.isEmpty {
                AttachmentStrip(images: model.theirImages) { model.theirImages.removeAll(where: $0) }
                    .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .contentShape(Rectangle())
        .overlay { dropHighlight(.theirs) }
        .dropDestination(for: URL.self) { urls, _ in drop(urls, into: .theirs) } isTargeted: { dropTarget = $0 ? .theirs : (dropTarget == .theirs ? nil : dropTarget) }
    }

    // MARK: You want to say

    private var intentSection: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 12, weight: .bold))
                Text("You want to say")
            }
            .pmlEyebrow()
            intentField
            DictationErrorBanner(dictation: dictation)
        }
        .padding(.top, 12).padding(.bottom, 12).padding(.leading, 14).padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PMLColor.accentSoft)
        .overlay { dropHighlight(.intent) }
        .dropDestination(for: URL.self) { urls, _ in drop(urls, into: .intent) } isTargeted: { dropTarget = $0 ? .intent : (dropTarget == .intent ? nil : dropTarget) }
    }

    private var intentField: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            ComposerTextArea(
                text: $model.intent,
                placeholder: dictation.isListening ? L("Listening…") : L("Confirm I can make it, but ask to push 30 minutes"),
                minHeight: 76, maxHeight: 130, focus: intentFocus)
            if !model.intentImages.isEmpty {
                AttachmentStrip(images: model.intentImages) { model.intentImages.removeAll(where: $0) }
                    .padding(.horizontal, 14).padding(.bottom, PMLSpace.s2)
            }
            ComposerToolbar(dictation: dictation, text: $model.intent, focused: anyFocus, addImages: pickImages)
        }
        .background(RoundedRectangle(cornerRadius: PMLRadius.inset, style: .continuous).fill(PMLColor.surface))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.inset, style: .continuous)
            .strokeBorder(PMLColor.lineStrong, lineWidth: 1))
    }

    // MARK: Images in

    private func add(_ images: [AttachedImage], to section: Section) {
        switch section {
        case .theirs: model.theirImages += images
        case .intent: model.intentImages += images
        }
    }

    private func drop(_ urls: [URL], into section: Section) -> Bool {
        let images = urls.compactMap { AttachedImage.make(fileURL: $0) }
        guard !images.isEmpty else { return false }
        add(images, to: section)
        return true
    }

    @ViewBuilder private func dropHighlight(_ section: Section) -> some View {
        if dropTarget == section {
            Rectangle().strokeBorder(PMLColor.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4])).allowsHitTesting(false)
        }
    }

    /// The + button: a picked image goes to the intent.
    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        add(panel.urls.compactMap { AttachedImage.make(fileURL: $0) }, to: .intent)
    }

    /// ⌘V with an image on the clipboard attaches it to the field that has focus instead of pasting text.
    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v",
                  let section = focused,
                  let images = AttachedImage.fromPasteboard() else { return event }
            add(images, to: section)
            return nil
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        pasteMonitor = nil
    }
}

// MARK: - Shared toolbar

/// The row under every composer field: screenshot, dictate, prompt, model and Send.
private struct ComposerToolbar: View {
    @Environment(AppModel.self) private var model
    @Bindable var dictation: DictationController
    @Binding var text: String
    /// True while any field of the composer has focus; popovers close then.
    var focused: Bool
    var showsPrompt = true
    var addImages: () -> Void

    @State private var showPrompt = false
    @State private var showModel = false
    @State private var showDictation = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ToolbarIcon(system: "plus", label: "Add a screenshot", action: addImages)
                ToolbarIcon(system: dictation.isListening ? "mic.fill" : "mic",
                            label: dictation.isListening ? "Stop dictation" : "Dictate",
                            tint: dictation.isListening ? PMLColor.accentText : PMLColor.inkSoft) {
                    dictation.toggle(base: text, motherLanguage: model.settings.motherLanguage) { text = $0 }
                }
                .popover(isPresented: $dictation.showSetup, arrowEdge: .top) { DictationSetup(dictation: dictation) }
                dictationMenuButton
                if showsPrompt {
                    ToolbarIcon(system: "doc.text", label: "View prompt", tint: showPrompt ? PMLColor.accentText : PMLColor.inkSoft) {
                        showModel = false; showDictation = false; showPrompt.toggle()
                    }
                    .popover(isPresented: $showPrompt, arrowEdge: .top) { PromptPopover(close: { showPrompt = false }) }
                }
            }
            if dictation.isListening { listeningStatus.padding(.leading, PMLSpace.s2) }
            Spacer(minLength: PMLSpace.s2)
            modelButton
            sendButton.padding(.leading, PMLSpace.s2)
        }
        .padding(6)
        .onChange(of: focused) { _, on in if on { showPrompt = false; showModel = false; showDictation = false } }
    }

    /// The small chevron beside the mic: input device, level and language.
    private var dictationMenuButton: some View {
        Button {
            showPrompt = false; showModel = false; showDictation.toggle()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(PMLColor.inkMuted)
                .frame(width: 16, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .help(Text("Dictation settings"))
        .accessibilityLabel(Text("Dictation settings"))
        .popover(isPresented: $showDictation, arrowEdge: .top) { DictationMenu(dictation: dictation) }
    }

    private var listeningStatus: some View {
        HStack(spacing: 6) {
            PulsingDot()
            Text("Listening").font(PMLFont.meta).foregroundStyle(PMLColor.accentText)
        }
    }

    private var modelButton: some View {
        Button {
            showPrompt = false; showModel.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: ModelLabel.short(model.settings.model)).fontWeight(.semibold).foregroundStyle(PMLColor.ink)
                if ModelCatalog.supportsEffort(model.settings.model) {
                    Text(verbatim: ModelLabel.effort(model.settings.effort)).foregroundStyle(PMLColor.inkMuted)
                }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(PMLColor.inkMuted)
            }
            .font(PMLFont.meta)
            .lineLimit(1)
            .padding(.horizontal, PMLSpace.s2)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .help(L("Model and effort"))
        .accessibilityLabel(Text("Model and effort"))
        .popover(isPresented: $showModel, arrowEdge: .top) { ModelMenu() }
    }

    private var sendButton: some View {
        Button {
            dictation.stop()
            Task { await model.send() }
        } label: {
            HStack(spacing: PMLSpace.s2) {
                if model.isSending { ProgressView().controlSize(.small) }
                Text(LocalizedStringKey(model.isSending ? "Sending…" : (model.hasResult ? "Send again" : "Send")))
                Text("⌘↵").font(PMLFont.kbd).opacity(0.75)
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .buttonStyle(PMLPrimaryButtonStyle(size: .medium))
        .disabled(!model.canSend)
        .help(sendTooltip)
    }

    private var sendTooltip: String {
        if model.canSend { return "" }
        if model.motherLanguageMissing { return L("Set your mother language in Settings first") }
        if model.isAsk { return L("Type your question first") }
        if model.activeModeTakesIntent { return L("Add their message or your intent first.") }
        return L("Select or paste text first")
    }
}

private struct DictationErrorBanner: View {
    var dictation: DictationController

    var body: some View {
        if let message = dictation.error {
            HStack(spacing: PMLSpace.s2) {
                Text(verbatim: message).font(PMLFont.hint).foregroundStyle(PMLColor.danger)
                if let url = dictation.errorOpensSettings {
                    Button("Open System Settings") { NSWorkspace.shared.open(url) }.buttonStyle(PMLGhostButtonStyle())
                }
            }
            .padding(PMLSpace.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).fill(PMLColor.dangerSoft))
        }
    }
}

/// Write, Understand and Ask: one box (the text, its screenshots and the toolbar).
/// Reply has its own two-part composer.
struct SingleComposer: View {
    @Environment(AppModel.self) private var model
    var focus: FocusState<Bool>.Binding

    @State private var dictation = DictationController()
    @State private var isFocused = false
    @State private var pasteMonitor: Any?
    @State private var dropping = false

    private var text: Binding<String> {
        @Bindable var model = model
        return model.isAsk ? $model.askPrompt : $model.inputText
    }

    private var label: LocalizedStringKey {
        if model.isAsk { return "Your question" }
        return model.activeMode == "Understand" ? "The message" : "Your text"
    }

    private var placeholder: String {
        model.isAsk ? L("Ask anything…") : L("Select some text, then press \(model.shortcutDisplay), or paste text or a screenshot here.")
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label).pmlEyebrow(PMLColor.inkMuted)
                Spacer()
                if !model.theirImages.isEmpty {
                    Text(verbatim: model.theirImages.count == 1 ? L("1 image") : L("\(model.theirImages.count) images"))
                        .font(PMLFont.meta).foregroundStyle(PMLColor.inkMuted)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14)
            ComposerTextArea(
                text: text,
                placeholder: dictation.isListening ? L("Listening…") : placeholder,
                minHeight: 130, maxHeight: 220, focus: focus)
            if !model.theirImages.isEmpty {
                AttachmentStrip(images: model.theirImages) { model.theirImages.removeAll(where: $0) }
                    .padding(.horizontal, 14).padding(.bottom, PMLSpace.s2)
            }
            DictationErrorBanner(dictation: dictation).padding(.horizontal, PMLSpace.s2)
            ComposerToolbar(dictation: dictation, text: text, focused: isFocused, showsPrompt: !model.isAsk, addImages: pickImages)
        }
        .background(PMLColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous)
            .strokeBorder(PMLColor.line, lineWidth: 1))
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: PMLRadius.card, style: .continuous)
                    .strokeBorder(PMLColor.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4])).allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.compactMap { AttachedImage.make(fileURL: $0) }
            guard !images.isEmpty else { return false }
            model.theirImages += images
            return true
        } isTargeted: { dropping = $0 }
        .onChange(of: focus.wrappedValue) { _, on in isFocused = on }
        .onChange(of: model.inputText) { old, new in
            // A paste lands as one big jump in length; run it through the same clean-up as captured text.
            if !model.isAsk, new.count - old.count > 20 { model.inputText = TextCleanup.beautify(new) }
        }
        .onAppear(perform: installPasteMonitor)
        .onDisappear { removePasteMonitor(); dictation.stop() }
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        model.theirImages += panel.urls.compactMap { AttachedImage.make(fileURL: $0) }
    }

    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v", isFocused,
                  let images = AttachedImage.fromPasteboard() else { return event }
            model.theirImages += images
            return nil
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        pasteMonitor = nil
    }
}


// MARK: - Pieces

/// Borderless multi-line field that grows with its text between `minHeight` and `maxHeight`, then scrolls.
private struct ComposerTextArea: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var focus: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Invisible copy of the text: it sets the height the editor grows to.
            Text(text.isEmpty ? " " : text + "\n")
                .font(PMLFont.input)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
                .opacity(0)
                .accessibilityHidden(true)
            TextEditor(text: $text)
                .font(PMLFont.input)
                .foregroundStyle(PMLColor.ink)
                .scrollContentBackground(.hidden)
                .focused(focus)
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(TextDropFilter())
            if text.isEmpty {
                Text(verbatim: placeholder)
                    .font(PMLFont.input)
                    .foregroundStyle(PMLColor.inkHint)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The text view inserts a dropped file's path as text. Narrow what it accepts to text, so
/// dropped files fall through to the composer, which attaches images.
private struct TextDropFilter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(view) }
    }

    private static func configure(_ view: NSView) {
        guard let content = view.window?.contentView else { return }
        let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        func find(_ v: NSView) -> NSTextView? {
            if let tv = v as? NSTextView, tv.convert(tv.bounds, to: nil).contains(center) { return tv }
            for sub in v.subviews { if let found = find(sub) { return found } }
            return nil
        }
        guard let textView = find(content) else { return }
        textView.unregisterDraggedTypes()
        textView.registerForDraggedTypes([.string, .rtf])
    }
}

/// Thumbnails in a wrapping row, each with a remove button on its top-right corner.
private struct AttachmentStrip: View {
    let images: [AttachedImage]
    var remove: ((AttachedImage) -> Bool) -> Void

    var body: some View {
        FlowLayout(spacing: PMLSpace.s2) {
            ForEach(images) { image in
                Image(nsImage: image.thumbnail)
                    .resizable().scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: PMLRadius.btn, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: PMLRadius.btn, style: .continuous).strokeBorder(PMLColor.line, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        Button { remove { $0.id == image.id } } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(PMLColor.onAccent)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(PMLColor.ink))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel(Text("Remove image"))
                    }
                    .padding(.top, 6).padding(.trailing, 6)
            }
        }
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: PMLRadius.btn, style: .continuous)
                .fill(hovering || configuration.isPressed ? PMLColor.surfaceSunken : .clear))
            .pmlFocusRing(radius: PMLRadius.btn)
            .onHover { hovering = $0 }
    }
}

private struct ToolbarIcon: View {
    let system: String
    let label: LocalizedStringKey
    var tint: Color = PMLColor.inkSoft
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

private struct PulsingDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(PMLColor.accent).frame(width: 7, height: 7)
            .opacity(on || reduceMotion ? 1 : 0.35)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - Popovers

/// The exact prompt the next Send will use. Edit it here to change the preset itself.
private struct PromptPopover: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void

    private var prompt: String {
        guard let preset = model.currentPreset else { return "" }
        guard !model.motherLanguageMissing else {
            return preset.prompt.replacingOccurrences(of: PresetLibrary.motherLanguageToken, with: "…")
        }
        var text = PromptBuilder.finalPrompt(
            preset: preset, motherLanguage: model.settings.motherLanguage,
            intent: model.intent, tabTakesIntent: model.activeModeTakesIntent, writeMyWay: model.writeMyWay)
        let count = model.theirImages.count + model.intentImages.count
        if count > 0 { text += "\n\nAttached: \(count) screenshot\(count == 1 ? "" : "s"). Read the text in \(count == 1 ? "it" : "them") as part of the message." }
        return text
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            HStack(spacing: PMLSpace.s2) {
                Text("Prompt").pmlEyebrow()
                if let preset = model.currentPreset, model.isEdited(preset) {
                    Text("Edited")
                        .font(PMLFont.badge).tracking(0.42).textCase(.uppercase)
                        .foregroundStyle(PMLColor.warning)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(PMLColor.warningSoft, in: RoundedRectangle(cornerRadius: PMLRadius.badge, style: .continuous))
                }
                Spacer()
                if !model.editingPrompt {
                    Button("Edit") { model.openPromptEditor() }.buttonStyle(PMLGhostButtonStyle())
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(PMLColor.inkMuted)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            if model.editingPrompt, let preset = model.currentPreset {
                editor(preset, draft: $model.promptDraft)
            } else {
                ScrollView {
                    Text(verbatim: prompt)
                        .font(PMLFont.body).foregroundStyle(PMLColor.inkSoft)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                if let flash = model.savedFlash {
                    Label(flash, systemImage: "checkmark.circle.fill").font(PMLFont.hint).foregroundStyle(PMLColor.success)
                }
            }
        }
        .padding(PMLSpace.s3)
        .frame(width: 380)
        .background(PMLColor.surface)
        .onDisappear { model.cancelPromptEdit() }
    }

    private func editor(_ preset: Preset, draft: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            TextEditor(text: draft)
                .font(PMLFont.body)
                .foregroundStyle(PMLColor.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 150)
                .background(PMLColor.surfaceSunken, in: RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous))
            Text("Saves to \(model.savedTargetLabel(preset)) in Settings")
                .font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
            HStack {
                Button("Cancel") { model.cancelPromptEdit() }.buttonStyle(PMLSecondaryButtonStyle())
                if model.isEdited(preset) || model.promptDraft != preset.originalPrompt {
                    Button("Reset to original") { model.revertPromptDraft() }.buttonStyle(PMLGhostButtonStyle())
                }
                Spacer()
                Button("Save & overwrite") { model.savePromptEdit() }.buttonStyle(PMLInkButtonStyle())
            }
        }
    }
}

/// The three things dictation can listen for, Mixed first. Used in the language page and in the first-use tips.
private struct DictationChoiceList: View {
    @Environment(AppModel.self) private var model
    var dictation: DictationController
    /// First use: if the saved choice needs a mother language that isn't set, ask for it straight away.
    var asksForMotherLanguage = false
    var onChosen: () -> Void = {}

    /// The choice that is waiting for a mother language to be picked.
    @State private var pickingMother: DictationChoice?
    @State private var search = ""

    private var mother: String { model.settings.motherLanguage.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Group { if pickingMother != nil { motherPicker } else { list } }
            .onAppear {
                if asksForMotherLanguage, dictation.choice.needsMotherLanguage, mother.isEmpty { pickingMother = dictation.choice }
            }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(DictationChoice.allCases, id: \.self) { choice in
                Button { select(choice) } label: {
                    HStack(spacing: PMLSpace.s2) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: PMLSpace.s2) {
                                Text(verbatim: title(choice)).font(PMLFont.select).foregroundStyle(PMLColor.ink).lineLimit(1)
                                if choice == .mixed {
                                    Text("Recommended")
                                        .font(PMLFont.badge).tracking(0.42).textCase(.uppercase)
                                        .foregroundStyle(PMLColor.accentText)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(PMLColor.accentSoft, in: RoundedRectangle(cornerRadius: PMLRadius.badge, style: .continuous))
                                }
                            }
                            Text(verbatim: detail(choice)).font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if dictation.choice == choice {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(PMLColor.accentText)
                        }
                    }
                    .padding(.horizontal, PMLSpace.s3).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous)
                        .fill(dictation.choice == choice ? PMLColor.accentSoft.opacity(0.6) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if dictation.choice != .mother { accentPicker }
        }
    }

    /// UK or US, for the English used alone or beside your mother language.
    private var accentPicker: some View {
        HStack(spacing: PMLSpace.s2) {
            Text("English accent").font(PMLFont.meta).foregroundStyle(PMLColor.inkMuted)
            Spacer()
            HStack(spacing: 2) {
                ForEach([("en-GB", "UK"), ("en-US", "US")], id: \.0) { id, label in
                    let selected = dictation.englishVariant == id
                    Button { dictation.englishVariant = id } label: {
                        Text(verbatim: label)
                            .font(PMLFont.meta).fontWeight(selected ? .bold : .medium)
                            .foregroundStyle(PMLColor.ink)
                            .frame(width: 44, height: 24)
                            .background(RoundedRectangle(cornerRadius: PMLRadius.seg, style: .continuous).fill(selected ? PMLColor.surface : .clear)
                                .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1.5, y: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).fill(PMLColor.surfaceSunken))
        }
        .padding(.horizontal, PMLSpace.s3).padding(.top, PMLSpace.s2)
    }

    private var motherPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PMLSpace.s2) {
                Button { pickingMother = nil } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(PMLColor.inkSoft)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
                TextField("Choose your mother language", text: $search).textFieldStyle(.plain).font(PMLFont.select)
            }
            .padding(.horizontal, PMLSpace.s3).padding(.vertical, PMLSpace.s2)
            Rectangle().fill(PMLColor.divider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Languages.all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { language in
                        Button {
                            model.settings.motherLanguage = language.name
                            model.saveSettings()
                            if let choice = pickingMother { dictation.choice = choice }
                            pickingMother = nil
                            search = ""
                            onChosen()
                        } label: {
                            HStack(spacing: PMLSpace.s2) {
                                Text(verbatim: language.flag)
                                Text(verbatim: language.name).font(PMLFont.select).foregroundStyle(PMLColor.ink)
                                Spacer()
                            }
                            .padding(.horizontal, PMLSpace.s3).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 220)
        }
    }

    private func select(_ choice: DictationChoice) {
        if choice.needsMotherLanguage && mother.isEmpty { pickingMother = choice; return }
        dictation.choice = choice
        onChosen()
    }

    private var englishLabel: String { dictation.englishVariant == "en-GB" ? "English (UK)" : "English (US)" }

    private func title(_ choice: DictationChoice) -> String {
        switch choice {
        case .mixed: L("Mixed")
        case .mother: L("Mother language")
        case .english: L("English")
        }
    }

    private func detail(_ choice: DictationChoice) -> String {
        switch choice {
        case .mixed: mother.isEmpty ? L("Your mother language and English, in one sentence") : "\(mother) + \(englishLabel)"
        case .mother: mother.isEmpty ? L("Not set") : mother
        case .english: englishLabel
        }
    }
}

/// Shown once, right after microphone and speech permission: which language to pick, and why.
private struct DictationSetup: View {
    @Environment(AppModel.self) private var model
    var dictation: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s3) {
            Text("Which language will you dictate in?").font(PMLFont.cardTitle).foregroundStyle(PMLColor.ink)
            VStack(alignment: .leading, spacing: PMLSpace.s2) {
                tip("arrow.left.arrow.right", "Mixed suits most people. Speak your language and drop in English words, like Vietnamese with English terms. It listens for both and keeps the words it's surest of once you stop.")
                tip("person.wave.2", "Only ever speaking one language? Pick English or your mother language.")
            }
            .padding(.horizontal, PMLSpace.s3)
            DictationChoiceList(dictation: dictation, asksForMotherLanguage: true)
            Text("You can change this any time from the arrow beside the mic.").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                .padding(.horizontal, PMLSpace.s3)
            HStack {
                Spacer()
                Button("Start dictating") { dictation.completeSetup() }
                    .buttonStyle(PMLPrimaryButtonStyle(size: .compact))
                    .disabled(dictation.choice.needsMotherLanguage && model.settings.motherLanguage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, PMLSpace.s3)
        }
        .padding(.vertical, PMLSpace.s3)
        .frame(width: 340)
        .background(PMLColor.surface)
    }

    private func tip(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: PMLSpace.s2) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(PMLColor.accentText).frame(width: 18)
            Text(text).font(PMLFont.body).foregroundStyle(PMLColor.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Input device, live level and language for dictation.
private struct DictationMenu: View {
    @Environment(AppModel.self) private var model
    var dictation: DictationController

    @State private var showLanguages = false
    @State private var inputs = DictationController.inputs()

    private var currentName: String {
        let mother = model.settings.motherLanguage.trimmingCharacters(in: .whitespaces)
        switch dictation.choice {
        case .english: return dictation.englishVariant == "en-GB" ? L("English (UK)") : L("English (US)")
        case .mother: return mother.isEmpty ? L("Mother language") : mother
        case .mixed: return L("Mixed")
        }
    }

    var body: some View {
        Group { showLanguages ? AnyView(languagePage) : AnyView(mainPage) }
            .frame(width: 300)
            .background(PMLColor.surface)
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: PMLSpace.s2) {
                Image(systemName: "mic").font(.system(size: 12)).foregroundStyle(PMLColor.inkMuted)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PMLColor.surfaceSunken)
                        Capsule().fill(PMLColor.accent).frame(width: max(6, geo.size.width * CGFloat(dictation.level)))
                            .animation(.linear(duration: 0.08), value: dictation.level)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, PMLSpace.s3).padding(.vertical, PMLSpace.s2)
            row(title: String(format: L("Default - %@"), DictationController.defaultInputName), selected: dictation.deviceUID.isEmpty) { dictation.deviceUID = "" }
            ForEach(inputs) { input in
                row(title: input.name, selected: dictation.deviceUID == input.id) { dictation.deviceUID = input.id }
            }
            Rectangle().fill(PMLColor.divider).frame(height: 1).padding(.vertical, 4)
            Text("Dictation settings").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted).padding(.horizontal, PMLSpace.s3)
            Button { showLanguages = true } label: {
                HStack {
                    Text("Language").font(PMLFont.select).foregroundStyle(PMLColor.ink)
                    Spacer()
                    Text(verbatim: currentName).font(PMLFont.meta).foregroundStyle(PMLColor.inkMuted).lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(PMLColor.inkMuted)
                }
                .padding(.horizontal, PMLSpace.s3).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, PMLSpace.s2)
    }

    private var languagePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PMLSpace.s2) {
                Button { showLanguages = false } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(PMLColor.inkSoft)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
                Text("Language").font(PMLFont.select).foregroundStyle(PMLColor.ink)
                Spacer()
            }
            .padding(.horizontal, PMLSpace.s3).padding(.vertical, PMLSpace.s2)
            Rectangle().fill(PMLColor.divider).frame(height: 1)
            DictationChoiceList(dictation: dictation) {
                if dictation.isListening { dictation.stop() }
                showLanguages = false
            }
            .padding(.vertical, 4)
        }
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PMLSpace.s2) {
                Text(verbatim: title).font(PMLFont.select).foregroundStyle(PMLColor.ink).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(PMLColor.accentText) }
            }
            .padding(.horizontal, PMLSpace.s3).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Model and effort for the next Send. Same settings as Settings → Advanced.
private struct ModelMenu: View {
    @Environment(AppModel.self) private var model

    private let efforts: [Effort] = [.low, .medium, .high]

    var body: some View {
        VStack(alignment: .leading, spacing: PMLSpace.s2) {
            Text("Model").pmlEyebrow(PMLColor.inkMuted).padding(.horizontal, PMLSpace.s2)
            ForEach(ModelCatalog.standardModels) { option in
                let selected = option.id == model.settings.model
                Button {
                    model.settings.model = option.id
                    model.saveSettings()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: ModelLabel.short(option.id)).font(PMLFont.select).foregroundStyle(PMLColor.ink)
                            Text(ModelLabel.tagline(option.id)).font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                        }
                        Spacer()
                        if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(PMLColor.accentText) }
                    }
                    .padding(.horizontal, PMLSpace.s2).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).fill(selected ? PMLColor.accentSoft : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Rectangle().fill(PMLColor.divider).frame(height: 1).padding(.vertical, 2)
            Text("Effort").pmlEyebrow(PMLColor.inkMuted).padding(.horizontal, PMLSpace.s2)
            if ModelCatalog.supportsEffort(model.settings.model) {
                HStack(spacing: 2) {
                    ForEach(efforts, id: \.self) { effort in
                        let selected = effort == model.settings.effort
                        Button {
                            model.settings.effort = effort
                            model.saveSettings()
                        } label: {
                            Text(verbatim: ModelLabel.effort(effort))
                                .font(PMLFont.meta).fontWeight(selected ? .bold : .medium)
                                .foregroundStyle(PMLColor.ink)
                                .frame(maxWidth: .infinity).frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: PMLRadius.seg, style: .continuous).fill(selected ? PMLColor.surface : .clear)
                                    .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1.5, y: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: PMLRadius.input, style: .continuous).fill(PMLColor.surfaceSunken))
                .padding(.horizontal, PMLSpace.s2)
            } else {
                Text("This model has no effort setting.").font(PMLFont.hint).foregroundStyle(PMLColor.inkMuted)
                    .padding(.horizontal, PMLSpace.s2)
            }
        }
        .padding(PMLSpace.s2)
        .frame(width: 232)
        .background(PMLColor.surface)
    }
}
