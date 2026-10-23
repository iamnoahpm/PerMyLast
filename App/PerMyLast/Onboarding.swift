import AppKit
import Observation
import SwiftUI
import PerMyLastCore

/// Where a captured selection came from, so the shortcut step can tell "it grabbed my selection" from "it used my clipboard".
enum CaptureSource: String {
    case selection, clipboard, service
}

/// First-run flow state: Welcome, First win (a canned sample, no account), Shortcut. Access (trial or own key) is opened on demand.
/// Persisted so quitting midway resumes; existing users (a key or an account already set up) never see it.
@MainActor
@Observable
final class OnboardingModel {
    static let shared = OnboardingModel()

    enum Step: String, CaseIterable {
        case welcome, firstWin = "first_win", shortcut, access
        /// The linear first-run flow. Access is not in it: it opens on demand ("Set up access", the checklist, a missing key),
        /// so nobody has to connect anything before they have seen the app work.
        static let sequence: [Step] = [.welcome, .firstWin, .shortcut]
        /// Position in the linear flow; nil for Access.
        var index: Int? { Self.sequence.firstIndex(of: self) }
    }

    private(set) var isActive: Bool
    var step: Step
    private(set) var shortcutWorked: Bool
    private(set) var hadFirstRealRun: Bool
    /// The last thing the shortcut caught while the shortcut step was open.
    private(set) var caught: (text: String, source: CaptureSource)?

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        shortcutWorked = d.bool(forKey: "onboardingShortcutWorked")
        hadFirstRealRun = d.bool(forKey: "hadFirstRealRun")
        step = Step(rawValue: d.string(forKey: "onboardingStep") ?? "") ?? .welcome
        if d.object(forKey: "onboardingDone") == nil {
            // Someone who already set the app up before this flow existed has nothing to be onboarded into.
            let existing = !AppModel.shared.apiKey.isEmpty || AccountModel.shared.signedIn || d.object(forKey: "settings") != nil
            if existing { d.set(true, forKey: "onboardingDone") }
        }
        isActive = d.object(forKey: "onboardingDone") == nil
    }

    // MARK: Moving through the flow

    /// Called when the popup first shows the flow.
    func didAppear() {
        if !defaults.bool(forKey: "onboardingStartedLogged") {
            defaults.set(true, forKey: "onboardingStartedLogged")
            FunnelLog.shared.log(.onboardingStarted)
        }
        logStep()
    }

    func go(to next: Step) {
        step = next
        defaults.set(next.rawValue, forKey: "onboardingStep")
        logStep()
    }

    func advance() {
        guard let i = step.index, i + 1 < Step.sequence.count else { return }
        go(to: Step.sequence[i + 1])
    }

    func back() {
        guard let i = step.index, i > 0 else { return }
        go(to: Step.sequence[i - 1])
    }

    /// "Skip setup": leave the flow; the Getting started checklist in the popup covers what is left.
    func skip() {
        FunnelLog.shared.log(.skipped, ["step": step.rawValue])
        close()
    }

    func finish() {
        let access = AccountModel.shared.signedIn ? "trial" : (AppModel.shared.apiKey.isEmpty ? "none" : "key")
        FunnelLog.shared.log(.completed, ["access": access])
        close()
    }

    /// Opens the flow again at a step ("Set up access" on an error, "Getting started" in the menu).
    func reopen(at target: Step) {
        step = target
        isActive = true
        logStep()
        WindowCoordinator.shared.showPopup()
    }

    private func close() {
        isActive = false
        defaults.set(true, forKey: "onboardingDone")
        defaults.set(Step.welcome.rawValue, forKey: "onboardingStep")
    }

    /// Dev aid (`PML_ONBOARDING=1`): start from the beginning whatever this Mac has set up.
    func restart(at start: Step = .welcome) {
        defaults.removeObject(forKey: "onboardingDone")
        caught = nil
        step = start
        isActive = true
    }

    #if DEBUG
    /// Debug menu aid: forget everything onboarding remembers (progress, shortcut test, first run) and start over.
    func resetForTesting() {
        for key in ["onboardingDone", "onboardingStep", "onboardingShortcutWorked", "hadFirstRealRun", "onboardingStartedLogged"] {
            defaults.removeObject(forKey: key)
        }
        shortcutWorked = false
        hadFirstRealRun = false
        restart()
        WindowCoordinator.shared.showPopup()
    }
    #endif

    private func logStep() { FunnelLog.shared.log(.stepViewed, ["step": step.rawValue]) }

    // MARK: Signals from the rest of the app

    /// The shortcut (or Services) delivered text. Returns true when the shortcut step consumed it as its test.
    func noteCapture(_ text: String, source: CaptureSource) -> Bool {
        guard isActive, step == .shortcut else { return false }
        caught = (text, source)
        // Clipboard text is the fallback when the selection could not be read: that is the failure this step exists to catch.
        guard source != .clipboard else { return true }
        shortcutWorked = true
        defaults.set(true, forKey: "onboardingShortcutWorked")
        FunnelLog.shared.log(.shortcutTested, ["via": source.rawValue])
        return true
    }

    /// A real run finished. The first one is the activation moment the funnel ends on.
    func noteRealRun() {
        guard !hadFirstRealRun else { return }
        hadFirstRealRun = true
        defaults.set(true, forKey: "hadFirstRealRun")
        FunnelLog.shared.log(.firstRealRun)
    }

    // MARK: Checklist (shown in the popup after the flow, while anything is open)

    struct Item: Identifiable {
        let id: Step
        let title: LocalizedStringKey
        let done: Bool
    }

    var hasAccess: Bool { !AppModel.shared.apiKey.isEmpty || AccountModel.shared.signedIn }

    var checklist: [Item] {
        [Item(id: .access, title: "Connect a trial or your Claude key", done: hasAccess),
         Item(id: .shortcut, title: "Try the shortcut in another app", done: shortcutWorked),
         Item(id: .firstWin, title: "Write your first real draft", done: hadFirstRealRun)]
    }

    var checklistComplete: Bool { checklist.allSatisfy(\.done) }
}
