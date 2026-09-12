import Foundation
import Testing
@testable import Snipcast

struct RecordingStoreTests {
    @Test func namesRecordingsByTimestamp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let date = cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 14, minute: 3, second: 7))!
        #expect(RecordingStore.recordingName(for: date, calendar: cal) == "Snipcast 2026-09-12 at 14.03.07.mp4")
    }

    @Test func trimmedNameSitsNextToSource() {
        let src = URL(fileURLWithPath: "/tmp/nowhere/Snipcast 2026-09-12 at 14.03.07.mp4")
        #expect(RecordingStore.trimmedURL(for: src).lastPathComponent == "Snipcast 2026-09-12 at 14.03.07 trimmed.mp4")
    }

    @Test func messagesLimitIsRoughlyOneHundredMegabytes() {
        #expect(!RecordingStore.exceedsMessagesLimit(99_000_000))
        #expect(RecordingStore.exceedsMessagesLimit(101_000_000))
    }
}
