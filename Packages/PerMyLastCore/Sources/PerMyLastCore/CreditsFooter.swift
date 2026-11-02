import Foundation

/// How the footer's credits indicator looks: quiet while there are plenty, louder as they run out.
public enum CreditsFooterLevel: Equatable, Sendable {
    case normal, low, empty
}

/// When the credits come back, in whole local calendar days.
public enum CreditsReset: Equatable, Sendable {
    case today, tomorrow
    case days(Int)

    /// "resets today", "resets tomorrow", "resets in 26 days".
    public var text: String {
        switch self {
        case .today: return "resets today"
        case .tomorrow: return "resets tomorrow"
        case .days(let n): return "resets in \(n) days"
        }
    }
}

public struct CreditsFooterState: Equatable, Sendable {
    public var level: CreditsFooterLevel
    /// Credits left, never negative. May exceed `total` (bonus credits).
    public var remaining: Int
    public var total: Int?
    /// Share of the period's credits left, 0...1. Nil when the total is unknown, so no bar is drawn.
    public var ratio: Double?
    /// Nil when there is no reset date.
    public var reset: CreditsReset?

    /// The visible line in English: "999 credits left", "Running low: 180 credits left · resets in 26 days",
    /// "No credits left · resets in 26 days". The app localizes from the fields above.
    public var text: String
}

/// Below this share of the period's credits the footer says "Running low".
public let creditsLowThreshold = 0.20

/// Derives the footer's state from the numbers alone, so it can be tested without any UI.
/// `remaining` below zero counts as zero; a `total` of zero or less counts as unknown.
public func getCreditsFooterState(
    remaining: Int, total: Int?, resetDate: Date?, now: Date = Date(),
    calendar: Calendar = .current, locale: Locale = .current
) -> CreditsFooterState {
    let left = max(0, remaining)
    let knownTotal = total.flatMap { $0 > 0 ? $0 : nil }
    let ratio = knownTotal.map { min(1, max(0, Double(left) / Double($0))) }

    let level: CreditsFooterLevel
    if left <= 0 { level = .empty }
    else if let ratio, ratio < creditsLowThreshold { level = .low }
    else { level = .normal }

    let reset = resetDate.map { creditsReset(until: $0, now: now, calendar: calendar) }
    let tail = reset.map { " · \($0.text)" } ?? ""
    let count = left.formatted(.number.locale(locale))
    let credits = left == 1 ? "\(count) credit left" : "\(count) credits left"

    let text: String
    switch level {
    case .normal: text = credits
    case .low: text = "Running low: \(credits)\(tail)"
    case .empty: text = "No credits left\(tail)"
    }
    return CreditsFooterState(level: level, remaining: left, total: knownTotal, ratio: ratio, reset: reset, text: text)
}

/// Whole calendar days from today to the reset date in the given calendar's time zone. A date in the past is "today".
public func creditsReset(until resetDate: Date, now: Date, calendar: Calendar = .current) -> CreditsReset {
    let from = calendar.startOfDay(for: now)
    let to = calendar.startOfDay(for: resetDate)
    let days = max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    switch days {
    case 0: return .today
    case 1: return .tomorrow
    default: return .days(days)
    }
}
