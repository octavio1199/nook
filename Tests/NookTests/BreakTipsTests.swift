import Foundation
import Testing
@testable import Nook

@Suite struct BreakTipsTests {
    private let base = Date(timeIntervalSinceReferenceDate: 20 * 100)

    @Test func stableWithinInterval() {
        #expect(BreakTips.tip(at: base, long: false) == BreakTips.tip(at: base.addingTimeInterval(19), long: false))
    }

    @Test func rotatesEveryInterval() {
        #expect(BreakTips.tip(at: base, long: false) != BreakTips.tip(at: base.addingTimeInterval(20), long: false))
    }

    @Test func cyclesThroughWholeList() {
        let seen = Set((0..<BreakTips.short.count).map { BreakTips.tip(at: base.addingTimeInterval(Double($0) * 20), long: false) })
        #expect(seen.count == BreakTips.short.count)
    }

    @Test func longBreakHasExtras() {
        #expect(BreakTips.long.count > BreakTips.short.count)
        #expect(BreakTips.long.contains { $0.emoji == "☕️" })
        #expect((8...10).contains(BreakTips.short.count))
    }

    @Test func negativeDatesAreSafe() {
        _ = BreakTips.tip(at: Date(timeIntervalSinceReferenceDate: -12345), long: true)
    }
}
