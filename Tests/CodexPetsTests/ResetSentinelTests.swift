import Foundation
import Testing
@testable import CodexPets

@Test
func resetSentinelSeedMatchesReferenceSnapshot() throws {
    #expect(ResetSentinelSeed.events.count == 53)
    #expect(ResetSentinelSeed.events.last?.id == "2098685367058612394")
    #expect(ResetSentinelSeed.events.last?.title == "全量重置已传播完成")
}

@Test
func resetSentinelProbabilityMatchesConditionalHistoryRule() throws {
    let origin = try #require(ResetSentinelSeed.parseDate("2026-01-01T00:00:00.000Z"))
    var dates = [origin]
    for interval in 1...7 {
        dates.append(try #require(dates.last).addingTimeInterval(Double(interval) * ResetSentinelLogic.day))
    }
    let events = dates.enumerated().map { index, date in
        ResetSentinelEvent(
            id: "\(index)",
            kind: .reset,
            title: "重置 \(index)",
            summary: "",
            announcedAt: date,
            sourceURL: URL(string: "https://x.com/thsottiaux/status/\(index)")!
        )
    }
    let now = try #require(dates.last).addingTimeInterval(2 * ResetSentinelLogic.day)

    #expect(ResetSentinelLogic.probability(events: events, now: now) == .value(percent: 20, sampleSize: 5))
}

@Test
func resetSentinelNextScanUsesHalfHourBoundary() throws {
    let now = try #require(ResetSentinelSeed.parseDate("2026-09-23T10:17:42.000Z"))
    let expected = try #require(ResetSentinelSeed.parseDate("2026-09-23T10:30:00.000Z"))

    #expect(ResetSentinelLogic.nextScan(after: now, calendar: Calendar(identifier: .gregorian)) == expected)
}
