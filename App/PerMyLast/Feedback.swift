import Foundation
import Observation
import PerMyLastCore

/// "How did this go?" after a run, and the optional step after it: sharing that run with us. Both are anonymous and both are the
/// person's choice. The rating row we store holds settings only (model, effort, mode, app and macOS version). The prompt, the text
/// they gave and the result leave the Mac only if they press "Share this run", on a screen that showed them exactly that text.
@MainActor
@Observable
final class FeedbackModel {
    static let shared = FeedbackModel()

    enum Rating: String, CaseIterable { case bad, fine, good }

    enum Stage: Equatable {
        case hidden
        case rating
        case consent(Rating)
        case thanks(shared: Bool)
    }

    /// Everything one run could share, captured when it finished. Never includes screenshots.
    struct Snapshot: Equatable {
        var prompt: String
        var input: String
        var output: String
        var mode: String
        var preset: String
        var model: String
        var effort: String
        var viaProxy: Bool
        var imageCount: Int
    }

    private(set) var stage = Stage.hidden
    private(set) var snapshot: Snapshot?
    private(set) var isSending = false
    /// What "Share this run" sends. Starts as the run's text; the person can edit or empty any of it first.
    var draftPrompt = ""
    var draftInput = ""
    var draftOutput = ""

    /// When to ask. Not at the start: a person needs to have used the product for real first, over more than one day.
    /// And not often: a long pause after an answer, a longer one after a dismissal.
    static let minRuns = 5
    static let minDaysSinceFirstRun = 2.0
    static let pauseAfterAnswer: TimeInterval = 21 * 86_400
    static let pauseAfterDismiss: TimeInterval = 45 * 86_400

    private let defaults = UserDefaults.standard
    private var feedbackID = UUID().uuidString.lowercased()
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    private var runCount: Int { defaults.integer(forKey: "feedbackRunCount") }
    private var firstRunAt: Date? { defaults.object(forKey: "feedbackFirstRunAt") as? Date }
    private var quietUntil: Date? { defaults.object(forKey: "feedbackQuietUntil") as? Date }

    /// Called when a run has finished and its answer is on screen.
    func runFinished(_ run: Snapshot, now: Date = Date()) {
        reset()
        defaults.set(runCount + 1, forKey: "feedbackRunCount")
        if firstRunAt == nil { defaults.set(now, forKey: "feedbackFirstRunAt") }
        guard canAsk(now: now) else { return }
        snapshot = run
        feedbackID = UUID().uuidString.lowercased()
        // Let the answer be read before anything appears under it.
        showTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.stage = .rating
        }
    }

    func canAsk(now: Date = Date()) -> Bool {
        guard AppModel.shared.settings.askForFeedback,
              AccountModel.shared.isConfigured,
              ProcessInfo.processInfo.environment["PML_NO_EVENTS"] != "1" else { return false }
        // `PML_FEEDBACK_NOW=1` skips the waiting rules so the bar can be looked at in a development run.
        if ProcessInfo.processInfo.environment["PML_FEEDBACK_NOW"] == "1" { return true }
        guard !OnboardingModel.shared.isActive,
              runCount >= Self.minRuns,
              let first = firstRunAt, now.timeIntervalSince(first) >= Self.minDaysSinceFirstRun * 86_400 else { return false }
        if let quiet = quietUntil, now < quiet { return false }
        return true
    }

    /// A new run, a new answer or a closed popup: the question no longer fits, so it goes without counting as an answer.
    func reset() {
        showTask?.cancel(); hideTask?.cancel()
        stage = .hidden
        snapshot = nil
    }

    // MARK: Choices

    func rate(_ rating: Rating) {
        quiet(for: Self.pauseAfterAnswer)
        if let s = snapshot { draftPrompt = s.prompt; draftInput = s.input; draftOutput = s.output }
        stage = .consent(rating)
        // The rating alone (settings, no text) counts as anonymous usage stats, so it follows that switch.
        if AppModel.shared.settings.shareAnonymousUsage { Task { await send(rating, shareText: false) } }
    }

    func share() {
        guard case .consent(let rating) = stage else { return }
        Task {
            await send(rating, shareText: true)
            show(.thanks(shared: true))
        }
    }

    func decline() {
        show(.thanks(shared: false))
    }

    /// The X on the rating bar, or "Don't ask again" on the consent step.
    func dismiss() {
        quiet(for: Self.pauseAfterDismiss)
        reset()
    }

    func neverAskAgain() {
        AppModel.shared.settings.askForFeedback = false
        AppModel.shared.saveSettings()
        reset()
    }

    // MARK: What is sent

    /// The settings lines of the preview, in the order they are sent.
    func settingsLog(for rating: Rating) -> [(key: String, value: String)] {
        guard let s = snapshot else { return [] }
        let app = AppModel.shared
        return [("rating", rating.rawValue), ("model", s.model), ("effort", s.effort), ("mode", s.mode), ("preset", s.preset),
                ("via", s.viaProxy ? "proxy" : "own_key"), ("app_version", app.appVersion), ("os_version", Self.osVersion),
                ("app_language", app.settings.appLanguage.rawValue), ("screenshots", "\(s.imageCount) (never sent)")]
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private func report(_ rating: Rating, shareText: Bool) -> FeedbackReport? {
        guard let s = snapshot else { return nil }
        let app = AppModel.shared
        return FeedbackReport(
            feedbackID: feedbackID, rating: rating.rawValue, appVersion: app.appVersion, osVersion: Self.osVersion,
            appLanguage: app.settings.appLanguage.rawValue, model: s.model, effort: s.effort, mode: s.mode, preset: s.preset,
            viaProxy: s.viaProxy, imageCount: s.imageCount,
            sharedText: shareText ? .init(prompt: draftPrompt, input: draftInput, output: draftOutput) : nil)
    }

    /// Best effort, like the funnel: a failed send is dropped and never shown.
    private func send(_ rating: Rating, shareText: Bool) async {
        guard let backend = AccountModel.shared.backend, let report = report(rating, shareText: shareText) else { return }
        isSending = shareText
        defer { isSending = false }
        try? await backend.sendFeedback(installIDHash: installIDHash(AccountModel.shared.installID()), report: report)
    }

    private func show(_ next: Stage) {
        stage = next
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }

    private func quiet(for seconds: TimeInterval) {
        defaults.set(Date().addingTimeInterval(seconds), forKey: "feedbackQuietUntil")
    }
}
