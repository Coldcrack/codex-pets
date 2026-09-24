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

@MainActor
@Test
func resetSentinelRefreshPreservesChineseTitlesAndLocalizesNewEvents() throws {
    let store = ResetSentinelStore()
    let existing = RemoteEvent(
        tweetID: "2098685367058612394",
        tweetURL: "https://x.com/thsottiaux/status/2098685367058612394",
        text: "Reset all propagated. Sweet dreams.",
        announcedAt: "2026-09-12T08:09:17.000Z",
        resetType: .reset
    )
    let newEvent = RemoteEvent(
        tweetID: "2100000000000000000",
        tweetURL: "https://x.com/thsottiaux/status/2100000000000000000",
        text: "A new reset card was added.",
        announcedAt: "2026-09-20T08:00:00.000Z",
        resetType: .banked
    )

    let events = try store.localizedEvents([newEvent, existing])

    #expect(events[0].title == "全量重置已传播完成")
    #expect(events[0].summary == "全量重置已传播完成")
    #expect(events[1].title == "第 2 次重置（重置卡）")
    #expect(events[1].summary == "A new reset card was added.")
}
