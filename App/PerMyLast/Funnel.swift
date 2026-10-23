import Foundation
import PerMyLastCore

/// Names of the anonymous first-run funnel events. Keep in step with EVENT_NAMES in backend/src/events.ts, which
/// refuses anything not listed there.
enum FunnelName: String {
    case onboardingStarted = "onboarding_started"
    case stepViewed = "onboarding_step_viewed"
    case sampleRun = "onboarding_sample_run"
    case copyClicked = "onboarding_copy_clicked"
    case accessibilityRequested = "onboarding_accessibility_requested"
    case shortcutTested = "onboarding_shortcut_tested"
    case trialCodeSent = "onboarding_access_trial_code_sent"
    case trialStarted = "onboarding_access_trial_started"
    case ownKeySaved = "onboarding_access_own_key_saved"
    case skipped = "onboarding_skipped"
    case completed = "onboarding_completed"
    case firstRealRun = "first_real_run"
}

/// Sends funnel events to the backend. Best effort: a failed send is dropped, never retried, never shown. Events carry
/// a hashed random install id and short step names only. `PML_NO_EVENTS=1` switches it off for development runs.
@MainActor
final class FunnelLog {
    static let shared = FunnelLog()

    private var queue: [FunnelEvent] = []
    private var flushTask: Task<Void, Never>?

    private var isOn: Bool {
        AppModel.shared.settings.shareAnonymousUsage
            && AccountModel.shared.isConfigured
            && ProcessInfo.processInfo.environment["PML_NO_EVENTS"] != "1"
    }

    func log(_ name: FunnelName, _ props: [String: String] = [:]) {
        guard isOn else { return }
        queue.append(FunnelEvent(name: name.rawValue, props: props))
        guard flushTask == nil else { return }
        // Batch events that arrive together (a step change logs two).
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.flush()
        }
    }

    private func flush() async {
        flushTask = nil
        let batch = Array(queue.prefix(20))
        queue.removeAll()
        guard !batch.isEmpty, let backend = AccountModel.shared.backend else { return }
        let id = installIDHash(AccountModel.shared.installID())
        try? await backend.sendEvents(installIDHash: id, appVersion: AppModel.shared.appVersion, events: batch)
    }
}
