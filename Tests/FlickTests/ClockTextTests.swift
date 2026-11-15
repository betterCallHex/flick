import Foundation
import Testing
@testable import Flick

struct ClockTextTests {
    @Test func showsMinutesAndSecondsUnderAnHour() {
        #expect(TimeInterval(65.9).clockText == "1:05")
    }

    @Test func showsHoursForLongVideos() {
        #expect(TimeInterval(3723).clockText == "1:02:03")
    }

    @Test func treatsUnknownTimeAsZero() {
        #expect(TimeInterval.nan.clockText == "0:00")
        #expect(TimeInterval(-4).clockText == "0:00")
    }
}
