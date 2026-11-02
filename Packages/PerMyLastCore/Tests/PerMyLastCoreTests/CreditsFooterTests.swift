import Foundation
import Testing
@testable import PerMyLastCore

@Suite("Credits footer")
struct CreditsFooterTests {
    private static let zone = TimeZone(identifier: "Pacific/Auckland")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = Self.zone
        return c
    }
    private let locale = Locale(identifier: "en_US")

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func state(_ remaining: Int, _ total: Int?, reset: Date? = nil, now: Date? = nil) -> CreditsFooterState {
        getCreditsFooterState(remaining: remaining, total: total, resetDate: reset,
                              now: now ?? date(2026, 11, 2), calendar: calendar, locale: locale)
    }

    // MARK: States

    @Test func plentyOfCreditsIsNormalWithAFullishBar() throws {
        let s = state(999, 1021)
        #expect(s.level == .normal)
        #expect(abs(try #require(s.ratio) - 0.978) < 0.001)
        #expect(s.text == "999 credits left")
    }

    @Test func lowShowsTheWordsAndTheReset() {
        let s = state(180, 1021, reset: date(2026, 11, 28))
        #expect(s.level == .low)
        #expect(s.text == "Running low: 180 credits left · resets in 26 days")
    }

    @Test func thresholdIsJustUnderTwentyPercent() {
        #expect(state(204, 1021).level == .low)
        #expect(state(205, 1021).level == .normal)
        #expect(state(20, 100).level == .normal)
        #expect(state(19, 100).level == .low)
    }

    @Test func emptyHasNoCreditsText() {
        let s = state(0, 1021, reset: date(2026, 11, 28))
        #expect(s.level == .empty)
        #expect(s.text == "No credits left · resets in 26 days")
    }

    @Test func oneCreditIsSingular() {
        #expect(state(1, 1021).text.hasSuffix("1 credit left"))
        #expect(state(1, 1021, reset: date(2026, 11, 3)).text == "Running low: 1 credit left · resets tomorrow")
        #expect(state(2, 1021).text.hasSuffix("2 credits left"))
    }

    @Test func numbersUseThousandsSeparators() {
        #expect(state(1021, 1021).text == "1,021 credits left")
    }

    // MARK: Relative reset

    @Test func resetCopyForTodayTomorrowAndLater() {
        let now = date(2026, 11, 2)
        #expect(creditsReset(until: date(2026, 11, 2, 23, 59), now: now, calendar: calendar).text == "resets today")
        #expect(creditsReset(until: date(2026, 11, 3), now: now, calendar: calendar).text == "resets tomorrow")
        #expect(creditsReset(until: date(2026, 11, 4), now: now, calendar: calendar).text == "resets in 2 days")
    }

    @Test func calendarDaysAreCountedAcrossMidnightNotIn24HourBlocks() {
        // 23:59 to 00:01 the next morning is one calendar day, though only two minutes apart.
        #expect(creditsReset(until: date(2026, 11, 3, 0, 1), now: date(2026, 11, 2, 23, 59), calendar: calendar) == .tomorrow)
        // 00:01 to 23:59 the same day is still today, though almost 24 hours apart.
        #expect(creditsReset(until: date(2026, 11, 2, 23, 59), now: date(2026, 11, 2, 0, 1), calendar: calendar) == .today)
    }

    @Test func daysFollowTheLocalTimeZone() {
        let instant = date(2026, 11, 2, 23, 0) // 23:00 in Auckland, still the 2nd
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // Same instant is the 2nd in Auckland but the 2nd/3rd boundary differs elsewhere; the reset is judged in the given zone.
        let resetInstant = date(2026, 11, 3, 1, 0)
        #expect(creditsReset(until: resetInstant, now: instant, calendar: calendar) == .tomorrow)
        #expect(creditsReset(until: resetInstant, now: instant, calendar: la) == .today)
    }

    @Test func resetAcrossDaylightSavingStillCountsCalendarDays() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        let now = c.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30))! // DST ends this day
        let reset = c.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 30))!
        #expect(creditsReset(until: reset, now: now, calendar: c) == .tomorrow)
    }

    // MARK: Edge cases

    @Test func unknownTotalHidesTheBarAndStillPicksTheState() {
        for total in [nil, 0, -5] as [Int?] {
            let normal = state(50, total)
            #expect(normal.ratio == nil)
            #expect(normal.total == nil)
            #expect(normal.level == .normal)
            #expect(state(0, total).level == .empty)
        }
    }

    @Test func bonusCreditsClampTheBarButKeepTheRealNumber() {
        let s = state(1500, 1021)
        #expect(s.ratio == 1)
        #expect(s.level == .normal)
        #expect(s.remaining == 1500)
        #expect(s.text == "1,500 credits left")
    }

    @Test func negativeRemainingCountsAsZero() {
        let s = state(-3, 1021)
        #expect(s.remaining == 0)
        #expect(s.ratio == 0)
        #expect(s.level == .empty)
    }

    @Test func pastResetDateSaysToday() {
        let s = state(0, 1021, reset: date(2026, 10, 20))
        #expect(s.reset == .today)
        #expect(s.text == "No credits left · resets today")
    }

    @Test func missingResetDateDropsTheFragment() {
        #expect(state(0, 1021).text == "No credits left")
        #expect(state(100, 1021).text == "Running low: 100 credits left")
        #expect(state(100, 1021).reset == nil)
    }
}
