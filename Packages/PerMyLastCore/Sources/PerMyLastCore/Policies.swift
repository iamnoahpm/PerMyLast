import Foundation

/// How long a Lifetime licence is trusted without contacting the server (NFR-11).
public enum OfflinePolicy {
    public static let graceDays = 14

    /// `fetchedAt` is when the server last confirmed the plan. A missing value means it never did.
    public static func lifetimeIsFresh(fetchedAt: Date?, now: Date = Date(), graceDays: Int = graceDays) -> Bool {
        guard let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) <= TimeInterval(graceDays) * 86_400
    }
}

/// The Lifetime update window (FR-P7): a licence includes updates for 12 months from purchase or renewal.
public enum UpdateWindow {
    public enum Status: Equatable, Sendable {
        case ok
        /// This build was released after the licence's updates ended.
        case renewalNeeded(updatesUntil: Date)
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Applies only to people on Lifetime alone: an active Pro plan is unaffected. A compatibility patch build is
    /// still allowed for 12 more months after updates end (24 months after purchase for a licence never renewed).
    public static func status(plan: PlanKind, updatesUntil: Date?, buildDate: Date, isPatchBuild: Bool, now: Date = Date()) -> Status {
        guard plan == .lifetime, let updatesUntil else { return .ok }
        if buildDate <= updatesUntil { return .ok }
        if isPatchBuild, let end = calendar.date(byAdding: .month, value: 12, to: updatesUntil), now <= end { return .ok }
        return .renewalNeeded(updatesUntil: updatesUntil)
    }
}
