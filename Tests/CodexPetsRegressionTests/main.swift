import Foundation
import CoreGraphics
import Darwin

final class TestRunner {
    private(set) var failures = 0

    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else {
            return
        }
        failures += 1
        FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
    }

    func require<T>(_ value: T?, _ message: String) -> T {
        guard let value else {
            failures += 1
            FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
            fatalError(message)
        }
        return value
    }
}

let runner = TestRunner()

var detailTransition = DetailTransitionState()
runner.check(detailTransition.phase == .hidden, "detail transition should start hidden")

let firstShow = detailTransition.begin(expanded: true)
runner.check(detailTransition.phase == .revealing, "show should enter revealing phase")

let interruptedHide = detailTransition.begin(expanded: false)
runner.check(interruptedHide != firstShow, "every transition should receive a new generation")
runner.check(detailTransition.phase == .hiding, "reverse transition should enter hiding phase")
runner.check(!detailTransition.completeShow(generation: firstShow), "stale show completion should be ignored")
runner.check(detailTransition.phase == .hiding, "stale show completion should not replace hiding phase")
runner.check(detailTransition.completeHide(generation: interruptedHide), "current hide completion should succeed")
runner.check(detailTransition.phase == .hidden, "hide completion should end hidden")

let finalShow = detailTransition.begin(expanded: true)
runner.check(detailTransition.completeShow(generation: finalShow), "current show completion should succeed")
runner.check(detailTransition.phase == .visible, "show completion should end visible")

var rapidDetailTransition = DetailTransitionState()
let rapidFirstShow = rapidDetailTransition.begin(expanded: true)
let rapidHide = rapidDetailTransition.begin(expanded: false)
let rapidFinalShow = rapidDetailTransition.begin(expanded: true)
runner.check(
    !rapidDetailTransition.completeShow(generation: rapidFirstShow),
    "rapid transition should ignore the first show completion"
)
runner.check(
    !rapidDetailTransition.completeHide(generation: rapidHide),
    "rapid transition should ignore the interrupted hide completion"
)
runner.check(
    rapidDetailTransition.phase == .revealing,
    "stale rapid completions should preserve the final revealing phase"
)
runner.check(
    rapidDetailTransition.completeShow(generation: rapidFinalShow),
    "rapid transition should accept the final show completion"
)
runner.check(
    rapidDetailTransition.phase == .visible,
    "rapid show-hide-show should end visible"
)

let detailFrames = DetailWindowFrameCalculator.calculate(
    screenFrame: CGRect(x: 100, y: 50, width: 1_440, height: 900),
    layoutWidth: 720,
    collapsedHeight: 38,
    detailHeight: 620,
    overlap: 4
)
let expectedDetailMaxY: CGFloat = 50 + 900 - 38 + 4
runner.check(
    detailFrames.collapsed.maxY == expectedDetailMaxY,
    "collapsed detail frame should preserve the shared top anchor"
)
runner.check(
    detailFrames.expanded.maxY == expectedDetailMaxY,
    "expanded detail frame should preserve the shared top anchor"
)
runner.check(
    detailFrames.collapsed.maxY == detailFrames.expanded.maxY,
    "detail frames should share the same maxY"
)
runner.check(
    detailFrames.collapsed.height == 4,
    "collapsed detail frame height should equal overlap"
)
runner.check(
    detailFrames.expanded.height == 620,
    "expanded detail frame height should equal detail height"
)

let petDetailFrames = DetailWindowFrameCalculator.calculateAbovePet(
    screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
    petFrame: CGRect(x: 1_180, y: 18, width: 236, height: 226),
    detailWidth: 368,
    detailHeight: 500,
    overlap: 18,
    gap: 8
)
runner.check(
    petDetailFrames.expanded.maxX <= 1_440 - PetMetrics.screenMargin,
    "pet detail should stay inside the right screen edge"
)
runner.check(
    petDetailFrames.expanded.minY == 252,
    "pet detail should open directly above the pet"
)
runner.check(
    petDetailFrames.collapsed.minY == petDetailFrames.expanded.minY,
    "pet detail animation should keep its bottom edge anchored"
)

runner.check(AppInfo.version == "0.0.1", "app info should expose version 0.0.1")
runner.check(AppInfo.displayVersion == "0.0.1", "app info should fall back to source version when bundle version is unavailable")

let resetCreditsNow = Date(timeIntervalSince1970: 1_784_500_000)
let appServerResetCreditsJSON = Data(#"""
{
  "availableCount": 3,
  "credits": [
    {"id":"late","resetType":"codexRateLimits","status":"available","expiresAt":1786557546000},
    {"id":"early","resetType":"codexRateLimits","status":"available","expiresAt":1785110188},
    {"id":"used","resetType":"codexRateLimits","status":"consumed","expiresAt":1785525156},
    {"id":"other","resetType":"otherRateLimits","status":"available","expiresAt":1785525156},
    {"id":"expired","resetType":"codexRateLimits","status":"available","expiresAt":1784499999}
  ]
}
"""#.utf8)
let decodedAppServerResetCredits = try RateLimitResetCreditsDecoder.decode(
    appServerResetCreditsJSON,
    now: resetCreditsNow
)
runner.check(
    decodedAppServerResetCredits?.availableCount == 3,
    "reset credit count should prefer the service value"
)
runner.check(
    decodedAppServerResetCredits?.credits.map(\.id) == ["early", "late"],
    "reset credits should filter invalid entries and sort Unix second/millisecond expiries"
)
runner.check(
    decodedAppServerResetCredits?.fetchedAt == resetCreditsNow,
    "reset credit fetch time should use the supplied now value"
)
runner.check(
    decodedAppServerResetCredits?.hasExpiryDetails == true,
    "reset credits should report available expiry details"
)

let cpaResetCreditsJSON = Data(#"""
{
  "available_count": "1",
  "credits": [
    {"id":"cpa","reset_type":"codex_rate_limits","status":"available","expires_at":"2026-08-01T03:12:00.000Z"}
  ]
}
"""#.utf8)
let decodedResetCredits = try RateLimitResetCreditsDecoder.decode(
    cpaResetCreditsJSON,
    now: resetCreditsNow
)
runner.check(
    decodedResetCredits?.availableCount == 1,
    "reset credit count should decode numeric strings"
)
runner.check(
    decodedResetCredits?.credits.count == 1,
    "reset credit expiry should decode snake-case ISO-8601 values"
)
let decodedResetExpiry = runner.require(
    decodedResetCredits?.credits.first?.expiresAt,
    "reset credit should include an expiry date"
)
runner.check(
    RateLimitResetCreditsFormatter.expiryText(
        decodedResetExpiry,
        timeZone: TimeZone(secondsFromGMT: 0)!
    ) == "2026/08/01 03:12",
    "reset credit expiry should use the agreed full date format"
)
runner.check(
    RateLimitResetCreditsFormatter.expiryText(
        decodedResetExpiry,
        timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!
    ) == "2026/08/01 11:12",
    "reset credit expiry should honor an injected GMT+8 time zone"
)

let plainISOResetCreditsJSON = Data(#"""
{
  "availableCount": 1,
  "credits": [
    {"id":"plain-iso","resetType":"codexRateLimits","status":"available","expiresAt":"2026-08-01T03:12:00Z"}
  ]
}
"""#.utf8)
let decodedPlainISOResetCredits = try RateLimitResetCreditsDecoder.decode(
    plainISOResetCreditsJSON,
    now: resetCreditsNow
)
runner.check(
    decodedPlainISOResetCredits?.credits.first?.expiresAt == decodedResetExpiry,
    "reset credit expiry should decode ISO-8601 values without fractional seconds"
)

let fallbackResetCreditsJSON = Data(#"""
{
  "credits": [
    {"id":"z","reset_type":"codex_rate_limits","status":"available","expires_at":"1786557546"},
    {"id":"a","reset_type":"codex_rate_limits","status":"available","expires_at":1786557546},
    {"id":"expired","reset_type":"codex_rate_limits","status":"available","expires_at":1784499999}
  ]
}
"""#.utf8)
let fallbackResetCredits = try RateLimitResetCreditsDecoder.decode(
    fallbackResetCreditsJSON,
    now: resetCreditsNow
)
runner.check(
    fallbackResetCredits?.availableCount == 2,
    "reset credit count should fall back to the valid credit count when omitted"
)
runner.check(
    fallbackResetCredits?.credits.map(\.id) == ["a", "z"],
    "reset credits with equal expiries should sort by identifier"
)

let zeroResetCredits = try RateLimitResetCreditsDecoder.decode(
    Data(#"{"available_count":-2,"credits":[]}"#.utf8),
    now: resetCreditsNow
)
runner.check(zeroResetCredits?.availableCount == 0, "negative service counts should clamp to zero")
let unrelatedResetCredits = try RateLimitResetCreditsDecoder.decode(
    Data(#"{"unrelated":true}"#.utf8),
    now: resetCreditsNow
)
runner.check(
    unrelatedResetCredits == nil,
    "payloads without a count or credits field should not create reset-credit data"
)

runner.check(
    ResetCreditsDisplay(resetCredits: nil) == nil,
    "missing reset-credit data should hide the entire indicator"
)
let zeroResetCreditsDisplay = runner.require(
    ResetCreditsDisplay(
        resetCredits: RateLimitResetCredits(
            availableCount: 0,
            credits: [],
            fetchedAt: resetCreditsNow
        )
    ),
    "zero reset credits should still produce display text"
)
runner.check(
    zeroResetCreditsDisplay.countText == "剩余重置次数：0",
    "zero reset credits should use the exact agreed count copy"
)
runner.check(
    !zeroResetCreditsDisplay.showsInfoButton,
    "zero reset credits should not show an information button"
)
let zeroCountWithStaleDetailsDisplay = runner.require(
    ResetCreditsDisplay(
        resetCredits: RateLimitResetCredits(
            availableCount: 0,
            credits: [
                RateLimitResetCredit(
                    id: "stale",
                    expiresAt: Date(timeIntervalSince1970: 1_786_557_546)
                )
            ],
            fetchedAt: resetCreditsNow
        )
    ),
    "an authoritative zero count should remain visible despite stale details"
)
runner.check(
    !zeroCountWithStaleDetailsDisplay.showsInfoButton,
    "an authoritative zero count should hide the information button"
)
runner.check(
    zeroCountWithStaleDetailsDisplay.expiryRows().isEmpty,
    "an authoritative zero count should not expose stale expiry rows"
)

let countOnlyResetCreditsDisplay = runner.require(
    ResetCreditsDisplay(
        resetCredits: RateLimitResetCredits(
            availableCount: 3,
            credits: [],
            fetchedAt: resetCreditsNow
        )
    ),
    "a service count without expiry details should remain visible"
)
runner.check(
    countOnlyResetCreditsDisplay.countText == "剩余重置次数：3",
    "reset-credit display should use the exact agreed copy"
)
runner.check(
    !countOnlyResetCreditsDisplay.showsInfoButton,
    "a service count without expiry details should not show an information button"
)

let detailedResetCreditsDisplay = runner.require(
    ResetCreditsDisplay(
        resetCredits: RateLimitResetCredits(
            availableCount: 2,
            credits: [
                RateLimitResetCredit(
                    id: "later",
                    expiresAt: Date(timeIntervalSince1970: 1_786_557_546)
                ),
                RateLimitResetCredit(
                    id: "earlier",
                    expiresAt: Date(timeIntervalSince1970: 1_785_110_188)
                )
            ],
            fetchedAt: resetCreditsNow
        )
    ),
    "expiry details should produce an information button"
)
runner.check(
    detailedResetCreditsDisplay.showsInfoButton,
    "available expiry details should show an information button"
)
runner.check(
    detailedResetCreditsDisplay.expiryRows(timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!) == [
        ResetCreditExpiryRow(ordinalText: "第 1 次", expiryText: "2026/07/27 07:56"),
        ResetCreditExpiryRow(ordinalText: "第 2 次", expiryText: "2026/08/13 01:59")
    ],
    "popover rows should sort expiries and use the agreed labels and date format"
)

let truncatedResetCreditsDisplay = runner.require(
    ResetCreditsDisplay(
        resetCredits: RateLimitResetCredits(
            availableCount: 1,
            credits: [
                RateLimitResetCredit(id: "later", expiresAt: Date(timeIntervalSince1970: 1_786_557_546)),
                RateLimitResetCredit(id: "earlier", expiresAt: Date(timeIntervalSince1970: 1_785_110_188))
            ],
            fetchedAt: resetCreditsNow
        )
    ),
    "service count should cap stale expiry details"
)
runner.check(
    truncatedResetCreditsDisplay.expiryDates.count == 1,
    "expiry rows should never exceed the authoritative available count"
)

runner.check(ResetCreditsPlacement.showsInLocalQuotaRow(label: "7d"), "local weekly quota row should show reset credits")
runner.check(!ResetCreditsPlacement.showsInLocalQuotaRow(label: "5h"), "local 5h quota row should not show reset credits")
runner.check(!ResetCreditsPlacement.showsInLocalQuotaRow(label: "周额度"), "local reset credits should only attach to the canonical 7d row")

runner.check(
    ResetCreditsLayout.inlineLayoutHeight == DetailPanelMetrics.quotaResetTextHeight,
    "the local quota layout should reserve the full information-button hit target height"
)

let snapshotFormatterTask = CodexTask(
    id: "snapshot-task",
    title: "父任务",
    status: .running,
    detailPrefix: "gpt-5.5 · 高推理",
    tokenCount: 12345,
    updatedAt: Date(timeIntervalSince1970: 0),
    activeSubagentCount: 3
)
let liveAgeTask = CodexTask(
    id: "live-age",
    title: "时间更新",
    status: .recent,
    detailPrefix: "gpt-5.6 · 超高推理",
    tokenCount: 1,
    updatedAt: Date(timeIntervalSince1970: 1_000)
)
runner.check(
    liveAgeTask.displayDetail(now: Date(timeIntervalSince1970: 8_200)) == "gpt-5.6 · 超高推理 · 2小时前",
    "task detail should recalculate its relative age from the current UI clock"
)
let snapshotFormatterSnapshot = UsageSnapshot(
    primaryPercent: 88,
    secondaryPercent: 66,
    resetCredits: RateLimitResetCredits(
        availableCount: 2,
        credits: [
            RateLimitResetCredit(id: "later", expiresAt: Date(timeIntervalSince1970: 4_100)),
            RateLimitResetCredit(id: "earlier", expiresAt: Date(timeIntervalSince1970: 4_000))
        ],
        fetchedAt: Date(timeIntervalSince1970: 3_900)
    ),
    usage24h: 111,
    usage7d: 222,
    usage30d: 333,
    tasks: [snapshotFormatterTask],
    isRunning: true,
    lastUpdated: Date(timeIntervalSince1970: 0),
    errorMessage: nil
)
let humanSnapshotLines = SnapshotOutputFormatter.humanLines(for: snapshotFormatterSnapshot)
runner.check(
    humanSnapshotLines.contains("task=运行中 父任务 12345"),
    "human snapshot task line should preserve the token count as the final field"
)
runner.check(
    !humanSnapshotLines.contains { $0.contains("subagents=") },
    "human snapshot output should not append subagent fields to task lines"
)
let jsonSnapshot = try JSONSerialization.jsonObject(
    with: SnapshotOutputFormatter.jsonData(for: snapshotFormatterSnapshot)
) as? [String: Any]
let jsonSnapshotTasks = jsonSnapshot?["tasks"] as? [[String: Any]]
runner.check(
    jsonSnapshotTasks?.first?["subagents"] as? Int == 3,
    "JSON snapshot output should expose active subagent counts"
)
let jsonResetCredits = jsonSnapshot?["reset_credits"] as? [String: Any]
runner.check(
    jsonResetCredits?["available_count"] as? Int == 2,
    "JSON snapshot output should expose the available reset-credit count"
)
runner.check(
    jsonResetCredits?["expires_at"] as? [Int64] == [4_000, 4_100],
    "JSON snapshot output should expose sorted reset-credit expiry epoch seconds"
)
let snapshotWithoutResetCredits = UsageSnapshot(
    primaryPercent: nil,
    secondaryPercent: nil,
    usage24h: 0,
    usage7d: 0,
    usage30d: 0,
    tasks: [],
    isRunning: false,
    lastUpdated: Date(timeIntervalSince1970: 0),
    errorMessage: nil
)
let jsonWithoutResetCredits = try JSONSerialization.jsonObject(
    with: SnapshotOutputFormatter.jsonData(for: snapshotWithoutResetCredits)
) as? [String: Any]
runner.check(
    jsonWithoutResetCredits?["reset_credits"] == nil,
    "JSON snapshot output should omit reset_credits when data is unavailable"
)
runner.check(
    TaskBadgeFormatter.subagentBadgeText(for: 3) == "子代理 3",
    "task row subagent badge should use compact text"
)
runner.check(
    TaskBadgeFormatter.subagentBadgeText(for: 0) == nil,
    "task row subagent badge should stay hidden for zero active subagents"
)
let previousRateLimitSnapshot = UsageSnapshot(
    primaryPercent: 88,
    secondaryPercent: 66,
    primaryResetsAt: Date(timeIntervalSince1970: 2_000),
    secondaryResetsAt: Date(timeIntervalSince1970: 3_000),
    resetCredits: RateLimitResetCredits(
        availableCount: 3,
        credits: [RateLimitResetCredit(id: "previous", expiresAt: Date(timeIntervalSince1970: 4_000))],
        fetchedAt: Date(timeIntervalSince1970: 900)
    ),
    usage24h: 1,
    usage7d: 2,
    usage30d: 3,
    tasks: [],
    isRunning: false,
    lastUpdated: Date(timeIntervalSince1970: 1_000),
    errorMessage: nil
)
let missingRateLimitSnapshot = UsageSnapshot(
    primaryPercent: nil,
    secondaryPercent: nil,
    primaryResetsAt: nil,
    secondaryResetsAt: nil,
    usage24h: 4,
    usage7d: 5,
    usage30d: 6,
    tasks: [],
    isRunning: false,
    lastUpdated: Date(timeIntervalSince1970: 1_100),
    errorMessage: nil
)
let stabilizedRateLimitSnapshot = missingRateLimitSnapshot.stabilizedRateLimits(against: previousRateLimitSnapshot)
runner.check(stabilizedRateLimitSnapshot.primaryPercent == 88, "stabilized snapshot should preserve missing 5h percent")
runner.check(stabilizedRateLimitSnapshot.primaryResetsAt == previousRateLimitSnapshot.primaryResetsAt, "stabilized snapshot should preserve missing 5h reset time")
runner.check(stabilizedRateLimitSnapshot.secondaryPercent == 66, "stabilized snapshot should preserve missing 7d percent")
runner.check(stabilizedRateLimitSnapshot.secondaryResetsAt == previousRateLimitSnapshot.secondaryResetsAt, "stabilized snapshot should preserve missing 7d reset time")
runner.check(
    stabilizedRateLimitSnapshot.resetCredits == previousRateLimitSnapshot.resetCredits,
    "stabilized snapshot should preserve reset credits when the current refresh omits them"
)
let zeroCreditRateLimitSnapshot = UsageSnapshot(
    primaryPercent: nil,
    secondaryPercent: nil,
    resetCredits: RateLimitResetCredits(
        availableCount: 0,
        credits: [],
        fetchedAt: Date(timeIntervalSince1970: 1_100)
    ),
    usage24h: 4,
    usage7d: 5,
    usage30d: 6,
    tasks: [],
    isRunning: false,
    lastUpdated: Date(timeIntervalSince1970: 1_100),
    errorMessage: nil
)
let stabilizedZeroCreditSnapshot = zeroCreditRateLimitSnapshot.stabilizedRateLimits(against: previousRateLimitSnapshot)
runner.check(
    stabilizedZeroCreditSnapshot.resetCredits?.availableCount == 0,
    "an explicit zero reset-credit count should replace stale nonzero data"
)
let rateLimitNow = Date(timeIntervalSince1970: 2_000)
let expiredRateLimitSnapshot = RateLimitSnapshot(
    primaryPercent: 42,
    secondaryPercent: 58,
    primaryResetsAt: 1_900,
    secondaryResetsAt: 2_500,
    capturedAt: rateLimitNow,
    isPrimaryCodexLimit: true
)
runner.check(expiredRateLimitSnapshot.primaryDisplayPercent(now: rateLimitNow) == 100, "expired 5h quota should display as restored")
runner.check(expiredRateLimitSnapshot.primaryDisplayResetDate(now: rateLimitNow) == nil, "expired 5h reset time should be hidden")
runner.check(expiredRateLimitSnapshot.secondaryDisplayResetDate(now: rateLimitNow) == Date(timeIntervalSince1970: 2_500), "future 7d reset time should be preserved")
let cachedAppServerRateLimits = RateLimitSnapshot(
    primaryPercent: nil,
    secondaryPercent: 97,
    primaryResetsAt: nil,
    secondaryResetsAt: 3_000,
    capturedAt: Date(timeIntervalSince1970: 2_000),
    isPrimaryCodexLimit: true,
    resetCredits: RateLimitResetCredits(
        availableCount: 2,
        credits: [],
        fetchedAt: Date(timeIntervalSince1970: 2_000)
    )
)
let newerLocalRateLimits = RateLimitSnapshot(
    primaryPercent: nil,
    secondaryPercent: 87,
    primaryResetsAt: nil,
    secondaryResetsAt: 3_000,
    capturedAt: Date(timeIntervalSince1970: 2_030),
    isPrimaryCodexLimit: true
)
let freshestLocalRateLimits = RateLimitSnapshot.freshest(
    appServer: cachedAppServerRateLimits,
    localFiles: newerLocalRateLimits
)
runner.check(
    freshestLocalRateLimits.secondaryPercent == 87,
    "a newer local rate-limit event should replace the cached app-server percentage"
)
runner.check(
    freshestLocalRateLimits.resetCredits == cachedAppServerRateLimits.resetCredits,
    "a newer local rate-limit event should preserve app-server reset-credit details"
)
let refreshedAppServerRateLimits = RateLimitSnapshot(
    primaryPercent: nil,
    secondaryPercent: 85,
    primaryResetsAt: nil,
    secondaryResetsAt: 3_000,
    capturedAt: Date(timeIntervalSince1970: 2_040),
    isPrimaryCodexLimit: true
)
runner.check(
    RateLimitSnapshot.freshest(
        appServer: refreshedAppServerRateLimits,
        localFiles: newerLocalRateLimits
    ).secondaryPercent == 85,
    "a freshly queried app-server percentage should remain authoritative"
)
let weeklyOnlyQuotaWindow = UsageQuotaWindow(
    id: "codex-weekly",
    shortLabel: "7d",
    remainingPercent: 93,
    resetsAt: Date(timeIntervalSince1970: 1784488110)
)
let weeklyOnlyRateLimitSnapshot = UsageSnapshot(
    primaryPercent: nil,
    secondaryPercent: 93,
    primaryResetsAt: nil,
    secondaryResetsAt: Date(timeIntervalSince1970: 1784488110),
    rateLimitWindows: [weeklyOnlyQuotaWindow],
    usage24h: 4,
    usage7d: 5,
    usage30d: 6,
    tasks: [],
    isRunning: false,
    lastUpdated: Date(timeIntervalSince1970: 1_200),
    errorMessage: nil
)
let stabilizedWeeklyOnlySnapshot = weeklyOnlyRateLimitSnapshot.stabilizedRateLimits(against: previousRateLimitSnapshot)
runner.check(stabilizedWeeklyOnlySnapshot.primaryPercent == nil, "weekly-only Codex quota should not preserve stale 5h percent")
runner.check(stabilizedWeeklyOnlySnapshot.displayRateLimitWindows.map(\.shortLabel) == ["7d"], "weekly-only Codex quota should only display the weekly window")
let appServerParserStore = CodexUsageStore(
    codexDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("codex-pets-reset-credit-parser"),
    ripgrepCandidates: [],
    appServerExecutable: "/missing/codex"
)
let appServerParserNow = Date(timeIntervalSince1970: 1_784_500_000)
let appServerRateLimitOutput = #"{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"resetsAt":1786557546,"windowDurationMins":10080}},"rateLimitResetCredits":{"available_count":"2","credits":[{"id":"later","reset_type":"codex_rate_limits","status":"available","expires_at":1786557546000},{"id":"earlier","reset_type":"codex_rate_limits","status":"available","expires_at":1785110188}]}}}"#
let parsedAppServerRateLimits = appServerParserStore.parseAppServerRateLimits(
    output: appServerRateLimitOutput,
    now: appServerParserNow
)
runner.check(
    parsedAppServerRateLimits?.displayWindows(now: appServerParserNow).map(\.shortLabel) == ["7d"],
    "app-server parsing should preserve a weekly-only Codex quota response"
)
runner.check(
    parsedAppServerRateLimits?.resetCredits?.availableCount == 2,
    "app-server parsing should attach reset credits from account/rateLimits/read"
)
runner.check(
    parsedAppServerRateLimits?.resetCredits?.credits.map(\.id) == ["earlier", "later"],
    "app-server parsing should use the shared reset-credit decoder and expiry ordering"
)
var fixedCalendar = Calendar(identifier: .gregorian)
fixedCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let formatterNow = fixedCalendar.date(from: DateComponents(year: 2030, month: 1, day: 1, hour: 23, minute: 0))!
let formatterTomorrow = fixedCalendar.date(from: DateComponents(year: 2030, month: 1, day: 2, hour: 1, minute: 30))!
let formatterLater = fixedCalendar.date(from: DateComponents(year: 2030, month: 1, day: 3, hour: 9, minute: 0))!
runner.check(Formatters.quotaResetTime(nil, now: formatterNow, calendar: fixedCalendar) == "--", "nil reset time should render as placeholder")
runner.check(Formatters.quotaResetTime(formatterTomorrow, now: formatterNow, calendar: fixedCalendar) == "明天 01:30", "reset formatter should calculate tomorrow relative to the supplied now")
runner.check(Formatters.quotaResetTime(formatterLater, now: formatterNow, calendar: fixedCalendar) == "1月3日", "reset formatter should show date for later reset times")
runner.check(Formatters.quotaResetTime(formatterLater, includeDate: true, now: formatterNow, calendar: fixedCalendar) == "1月3日 09:00", "weekly reset formatter should show month, day, hour, and minute")
runner.check(
    DetailPanelMetrics.detailCoveredTopHeight(safeAreaTop: 38) == 18,
    "detail panel should account for the covered screen-safe area"
)
runner.check(
    DetailPanelMetrics.quotaResetTopPadding(safeAreaTop: 38) >= 25,
    "quota reset text should start below the covered screen-safe area"
)
final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}

runner.check(RefreshCadence.pendingSnapshotDelay(for: 2) == 1, "coalesced snapshot refresh should wait at least one second")
runner.check(RefreshCadence.pendingSnapshotDelay(for: 6) == 3, "coalesced snapshot refresh should cap short follow-up waits")
runner.check(RefreshCadence.pendingUsageDelay(for: 30) == 15, "coalesced usage refresh should avoid tight restart loops")
runner.check(RefreshCadence.pendingUsageDelay(for: 300) == 60, "coalesced usage refresh should cap long follow-up waits")
runner.check(UsageRefreshCadence.refreshInterval(configured: 30, lastDuration: nil) == 120, "period usage refresh should not run more often than the power-safe floor")
runner.check(UsageRefreshCadence.refreshInterval(configured: 300, lastDuration: nil) == 300, "period usage refresh should respect larger configured intervals")
runner.check(UsageRefreshCadence.refreshInterval(configured: 120, lastDuration: 6) == 180, "slow usage scans should push the next refresh farther out")
runner.check(UsageRefreshCadence.refreshInterval(configured: 600, lastDuration: 40) == 1_200, "very slow usage scans should adapt without exceeding the cap")
let usageFileChangeNow = Date(timeIntervalSince1970: 1_000)
runner.check(
    UsageRefreshCadence.fileChangeDelay(now: usageFileChangeNow, lastCompletedAt: nil) == 4,
    "the first watched session change should settle briefly before refreshing usage"
)
runner.check(
    UsageRefreshCadence.fileChangeDelay(
        now: usageFileChangeNow,
        lastCompletedAt: usageFileChangeNow.addingTimeInterval(-30)
    ) == 30,
    "watched session changes should respect the one-minute usage refresh throttle"
)
runner.check(
    UsageRefreshCadence.fileChangeDelay(
        now: usageFileChangeNow,
        lastCompletedAt: usageFileChangeNow.addingTimeInterval(-90)
    ) == 4,
    "stale period usage should refresh promptly after a watched session change"
)

let decoder = CodexSessionEventDecoder()
let decoderNow = Date(timeIntervalSince1970: 1_800_000_000)
let decoderFormatter = ISO8601DateFormatter()
let decoderTimestamp = decoderFormatter.string(from: decoderNow)
let decoderText = """
{"timestamp":"\(decoderTimestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"xhigh"}}
{"timestamp":"\(decoderTimestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"## My request for Codex:\\n集中解析 JSONL"}]}}
{"timestamp":"\(decoderTimestamp)","type":"response_item","payload":{"type":"function_call","name":"exec_command"}}
{"timestamp":"\(decoderFormatter.string(from: decoderNow.addingTimeInterval(1)))","type":"event_msg","payload":{"type":"task_complete"}}
"""
runner.check(decoder.title(from: decoderText) == "集中解析 JSONL", "session decoder should normalize Codex request titles")
runner.check(decoder.runtimeInfo(from: decoderText)?.model == "gpt-5.5", "session decoder should read turn context model")
runner.check(decoder.runtimeInfo(from: decoderText)?.reasoningEffort == "xhigh", "session decoder should read turn context effort")
runner.check(decoder.activityInfo(from: decoderText)?.latestDone != nil, "session decoder should detect task completion events")
runner.check(
    decoder.tokenCountTokens(from: #"{"timestamp":"\#(decoderTimestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":123}}}}"#) == 123,
    "session decoder should extract token_count totals"
)

let settingsSuiteName = "CodexPetsRegressionTests-\(UUID().uuidString)"
let settingsDefaults = runner.require(
    UserDefaults(suiteName: settingsSuiteName),
    "settings regression defaults should be available"
)
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
let settings = CodexPetsSettings(
    defaults: settingsDefaults,
    launchAtLoginManager: FakeLaunchAtLoginManager()
)
settings.activeRefreshInterval = 5
settings.showPeriodUsage = false
let reloadedSettings = CodexPetsSettings(
    defaults: settingsDefaults,
    launchAtLoginManager: FakeLaunchAtLoginManager()
)
runner.check(reloadedSettings.activeRefreshInterval == 5, "local refresh interval should persist")
runner.check(!reloadedSettings.showPeriodUsage, "local usage visibility should persist")
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)

let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("CodexPetsRegression-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: tempRoot)
}

let stateDatabase = tempRoot.appendingPathComponent("state_5.sqlite").path
let logsDatabase = tempRoot.appendingPathComponent("logs_2.sqlite").path
_ = try Shell.run("/usr/bin/sqlite3", [
    stateDatabase,
    """
    create table threads(
      id text,
      title text,
      tokens_used integer,
      model text,
      reasoning_effort text,
      rollout_path text,
      updated_at integer,
      archived integer default 0
    );
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    logsDatabase,
    """
    create table logs(
      thread_id text,
      ts integer,
      target text,
      feedback_log_body text
    );
    """
])

let sessionID = "019e7169-d297-74c1-a61a-8e5a82acab34"
let subagentSessionID = "019ec23f-2f8e-7d50-a71d-b8a2ba679fd4"
let historicalSubagentSessionID = "019ec23f-7777-7d50-a71d-b8a2ba679fd4"
let parentOnlySessionID = "019e073a-c032-74e2-966e-b85ede0c9ccb"
let parentOnlySubagentID = "019ec23f-344a-7171-99d0-f1c2fe671252"
let staleParentSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd1"
let staleParentSubagentID = "019ec23f-5555-7171-99d0-f1c2fe671252"
let longMetaParentSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd0"
let longMetaSubagentID = "019ec23f-4444-7171-99d0-f1c2fe671252"
let completedSessionID = "019e073a-c032-74e2-966e-b85ede0c9ccd"
let completedFinalAnswerSessionID = "019e073a-c032-74e2-966e-b85ede0c9ccf"
let completedLogFinalSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd4"
let dbBackedSessionID = "019e073a-c032-74e2-966e-b85ede0c9cce"
let staleDBTokenSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd2"
let activeToolCallSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd3"
let sessionDirectory = tempRoot
    .appendingPathComponent("sessions/2026/06/14", isDirectory: true)
try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
let rolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-00-\(sessionID).jsonl")
let now = Date()
let timestamp = ISO8601DateFormatter().string(from: now)
let primaryResetAt = Int(now.timeIntervalSince1970) + 3_600
let secondaryResetAt = Int(now.timeIntervalSince1970) + 3 * 24 * 60 * 60
let rolloutBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"xhigh","collaboration_mode":{"settings":{"reasoning_effort":"xhigh"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"正在运行的 Codex 任务"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":90000}}}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":12345}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":12,"resets_at":\(primaryResetAt)},"secondary":{"used_percent":34,"resets_at":\(secondaryResetAt)}}}}
"""
try rolloutBody.write(to: rolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: rolloutPath.path)

let subagentRolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-01-\(subagentSessionID).jsonl")
let subagentRolloutBody = """
{"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(subagentSessionID)","parent_thread_id":"\(sessionID)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(sessionID)","depth":1,"agent_nickname":"Test","agent_role":"explorer"}}},"thread_source":"subagent","agent_nickname":"Test","agent_role":"explorer"}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":9000000}}}}
{"timestamp":"\(timestamp)","type":"world_state","payload":{"kind":"inherited_parent_history"}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":8000000}}}}
{"timestamp":"\(timestamp)","type":"world_state","payload":{"kind":"child_start"}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"子代理任务不应该显示"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":10000}}}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":23456}}}}
"""
try subagentRolloutBody.write(to: subagentRolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: subagentRolloutPath.path)

let historicalSubagentRolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-04-\(historicalSubagentSessionID).jsonl")
let historicalSubagentRolloutBody = """
{"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(historicalSubagentSessionID)","parent_thread_id":"\(sessionID)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(sessionID)","depth":1,"agent_nickname":"Old","agent_role":"reviewer"}}},"thread_source":"subagent","agent_nickname":"Old","agent_role":"reviewer"}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"历史子代理不应该计入当前子代理数量"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":50000}}}}
"""
try historicalSubagentRolloutBody.write(to: historicalSubagentRolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-600)], ofItemAtPath: historicalSubagentRolloutPath.path)

let parentOnlyRolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-02-\(parentOnlySessionID).jsonl")
let parentOnlyBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","collaboration_mode":{"settings":{"reasoning_effort":"high"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"只有子代理活跃的父任务"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":34567}}}}
"""
try parentOnlyBody.write(to: parentOnlyRolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-600)], ofItemAtPath: parentOnlyRolloutPath.path)

let parentOnlySubagentPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-03-\(parentOnlySubagentID).jsonl")
let parentOnlySubagentBody = """
{"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(parentOnlySubagentID)","parent_thread_id":"\(parentOnlySessionID)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(parentOnlySessionID)","depth":1,"agent_nickname":"Worker","agent_role":"reviewer"}}},"thread_source":"subagent","agent_nickname":"Worker","agent_role":"reviewer"}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"另一个子代理任务不应该显示"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":45678}}}}
"""
try parentOnlySubagentBody.write(to: parentOnlySubagentPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: parentOnlySubagentPath.path)

let staleParentPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-10-\(staleParentSessionID).jsonl")
let staleParentBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","collaboration_mode":{"settings":{"reasoning_effort":"high"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"父会话超出当前任务范围但子代理正在运行"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":123000}}}}
"""
try staleParentBody.write(to: staleParentPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-2 * 24 * 60 * 60)], ofItemAtPath: staleParentPath.path)

let staleParentSubagentPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-11-\(staleParentSubagentID).jsonl")
let staleParentSubagentBody = """
{"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(staleParentSubagentID)","parent_thread_id":"\(staleParentSessionID)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(staleParentSessionID)","depth":1,"agent_nickname":"Worker","agent_role":"explorer"}}},"thread_source":"subagent","agent_nickname":"Worker","agent_role":"explorer"}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"子代理仍在输出"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":321000}}}}
"""
try staleParentSubagentBody.write(to: staleParentSubagentPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: staleParentSubagentPath.path)

let longMetaParentPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-08-\(longMetaParentSessionID).jsonl")
let longMetaParentBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","collaboration_mode":{"settings":{"reasoning_effort":"high"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"超长 session_meta 的父任务"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":22222}}}}
"""
try longMetaParentBody.write(to: longMetaParentPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-600)], ofItemAtPath: longMetaParentPath.path)

let longSessionMetaPadding = String(repeating: "x", count: 80_000)
let longMetaSubagentPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-09-\(longMetaSubagentID).jsonl")
let longMetaSubagentBody = """
{"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(longMetaSubagentID)","parent_thread_id":"\(longMetaParentSessionID)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(longMetaParentSessionID)","depth":1,"agent_nickname":"Long","agent_role":"explorer"}}},"thread_source":"subagent","agent_nickname":"Long","agent_role":"explorer","base_instructions":{"text":"\(longSessionMetaPadding)"}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"超长子代理任务不应该显示"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":11111}}}}
"""
try longMetaSubagentBody.write(to: longMetaSubagentPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: longMetaSubagentPath.path)
_ = try Shell.run("/usr/bin/sqlite3", [
    stateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(longMetaSubagentID)', '数据库里的子代理不应该显示', 11111, 'gpt-5.5', 'xhigh', '\(longMetaSubagentPath.path)', \(Int(now.timeIntervalSince1970)), 0);
    """
])

let completedRolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-05-\(completedSessionID).jsonl")
let completedBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","collaboration_mode":{"settings":{"reasoning_effort":"high"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"已经完成的任务"}]}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"完成"}],"phase":"final"}}
"""
try completedBody.write(to: completedRolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: completedRolloutPath.path)

let completedFinalAnswerRolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-07-\(completedFinalAnswerSessionID).jsonl")
let completedFinalAnswerBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","collaboration_mode":{"settings":{"reasoning_effort":"high"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"刚刚完成但还很新的任务"}]}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"完成"}],"phase":"final_answer"}}
{"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"task_complete","turn_id":"019ed38c-b572-7140-a10f-e4c982c36066","completed_at":\(Int(now.timeIntervalSince1970)),"duration_ms":1200}}
"""
try completedFinalAnswerBody.write(to: completedFinalAnswerRolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: completedFinalAnswerRolloutPath.path)

let completedLogFinalRolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-14-\(completedLogFinalSessionID).jsonl")
let completedLogFinalBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","collaboration_mode":{"settings":{"reasoning_effort":"high"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"日志 final 完成的任务"}]}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"完成"}],"phase":"final"}}
"""
try completedLogFinalBody.write(to: completedLogFinalRolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: completedLogFinalRolloutPath.path)
_ = try Shell.run("/usr/bin/sqlite3", [
    stateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(completedLogFinalSessionID)', '日志 final 完成的任务', 888, 'gpt-5.5', 'high', '\(completedLogFinalRolloutPath.path)', \(Int(now.timeIntervalSince1970)), 0);
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    logsDatabase,
    """
    insert into logs(thread_id, ts, target, feedback_log_body)
    values
      ('\(completedLogFinalSessionID)', \(Int(now.timeIntervalSince1970) - 30), 'codex_otel.trace_safe', '{"type":"event_msg","payload":{"type":"response.output_text.delta"}}'),
      ('\(completedLogFinalSessionID)', \(Int(now.timeIntervalSince1970) - 20), 'codex_otel.trace_safe', '{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"final"}}');
    """
])

let dbBackedRolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-06-\(dbBackedSessionID).jsonl")
let dbBackedBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","collaboration_mode":{"settings":{"reasoning_effort":"high"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"数据库已有 token 的旧任务"}]}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"完成"}],"phase":"final"}}
"""
try dbBackedBody.write(to: dbBackedRolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: dbBackedRolloutPath.path)
_ = try Shell.run("/usr/bin/sqlite3", [
    stateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(dbBackedSessionID)', '数据库已有 token 的旧任务', 777, 'gpt-5.5', 'high', '\(dbBackedRolloutPath.path)', \(Int(now.timeIntervalSince1970) - 7 * 24 * 60 * 60), 0);
    """
])

let staleDBTokenRolloutPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-12-\(staleDBTokenSessionID).jsonl")
let staleDBTokenBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"high","collaboration_mode":{"settings":{"reasoning_effort":"high"}}}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"数据库 token 滞后的运行中任务"}]}}
{"timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":120000000}}}}
"""
try staleDBTokenBody.write(to: staleDBTokenRolloutPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: staleDBTokenRolloutPath.path)
_ = try Shell.run("/usr/bin/sqlite3", [
    stateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(staleDBTokenSessionID)', '数据库 token 滞后的运行中任务', 13, 'gpt-5.5', 'high', '\(staleDBTokenRolloutPath.path)', \(Int(now.timeIntervalSince1970)), 0);
    """
])

let activeToolCallPath = sessionDirectory
    .appendingPathComponent("rollout-2026-06-14T02-20-13-\(activeToolCallSessionID).jsonl")
let activeToolCallActivity = ISO8601DateFormatter().string(from: now.addingTimeInterval(-240))
let activeToolCallItemDone = ISO8601DateFormatter().string(from: now.addingTimeInterval(-230))
let activeToolCallBody = """
{"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-5.5","effort":"xhigh","collaboration_mode":{"settings":{"reasoning_effort":"xhigh"}}}}
{"timestamp":"\(activeToolCallActivity)","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{}"}}
{"timestamp":"\(activeToolCallItemDone)","type":"event_msg","payload":{"type":"response.function_call_arguments.done"}}
{"timestamp":"\(activeToolCallItemDone)","type":"event_msg","payload":{"type":"response.output_item.done"}}
{"timestamp":"\(activeToolCallItemDone)","type":"event_msg","payload":{"type":"response.completed"}}
"""
try activeToolCallBody.write(to: activeToolCallPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: activeToolCallPath.path)
_ = try Shell.run("/usr/bin/sqlite3", [
    stateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(activeToolCallSessionID)', '工具调用仍在运行', 21, 'gpt-5.5', 'xhigh', '\(activeToolCallPath.path)', \(Int(now.timeIntervalSince1970)), 0);
    """
])

let localStore = CodexUsageStore(codexDirectory: tempRoot)
let localSnapshot = localStore.loadSnapshot(
    includePeriodUsage: false,
    bypassFastCache: true,
    rateLimitSource: .localFilesOnly,
    taskHistoryRange: .day,
    now: now
)
runner.check(localSnapshot.isRunning, "recent session rollout should mark local Codex as running")
runner.check(localSnapshot.tasks.contains { $0.id == sessionID && $0.status == .running }, "recent session rollout should appear in running task list")
runner.check(localSnapshot.tasks.first { $0.id == sessionID }?.title == "正在运行的 Codex 任务", "session rollout should use the user message as task title")
runner.check(localSnapshot.tasks.first { $0.id == sessionID }?.detailPrefix.contains("gpt-5.5 · 超高推理") == true, "session rollout should use turn context model and effort")
runner.check(!localSnapshot.tasks.contains { $0.id == subagentSessionID }, "subagent rollout should not appear as a separate local task")
runner.check(!localSnapshot.tasks.contains { $0.id == parentOnlySubagentID }, "subagent-only activity should still hide the child task")
runner.check(!localSnapshot.tasks.contains { $0.id == longMetaSubagentID }, "subagent rollout with long session metadata should still hide the child task")
runner.check(localSnapshot.tasks.contains { $0.id == parentOnlySessionID && $0.status == .running }, "recent subagent activity should mark the parent task running")
runner.check(localSnapshot.tasks.contains { $0.id == longMetaParentSessionID && $0.status == .running }, "long session metadata subagent activity should mark the parent task running")
runner.check(localSnapshot.tasks.first { $0.id == parentOnlySessionID }?.detailPrefix.contains("gpt-5.5 · 高推理") == true, "parent running through subagent activity should use turn context model and effort")
runner.check(localSnapshot.tasks.first { $0.id == sessionID }?.activeSubagentCount == 1, "parent task should only show currently active subagents")
runner.check(localSnapshot.tasks.first { $0.id == parentOnlySessionID }?.activeSubagentCount == 1, "parent running through subagent activity should show one subagent")
runner.check(localSnapshot.tasks.first { $0.id == longMetaParentSessionID }?.activeSubagentCount == 1, "parent running through long metadata subagent activity should show one subagent")
runner.check(localSnapshot.tasks.contains { $0.id == staleParentSessionID && $0.status == .running }, "active subagent should synthesize a running parent task even when the parent is outside the task range")
runner.check(localSnapshot.tasks.first { $0.id == sessionID }?.tokenCount == 185801, "parent task token count should include parent and all subagent session totals")
runner.check(localSnapshot.tasks.first { $0.id == sessionID }?.tokenCount != 17_185_801, "parent task token count should exclude history copied into spawned subagent rollouts")
runner.check(localSnapshot.tasks.first { $0.id == parentOnlySessionID }?.tokenCount == 80245, "parent running through subagent activity should include subagent token usage")
runner.check(localSnapshot.tasks.first { $0.id == longMetaParentSessionID }?.tokenCount == 33333, "parent running through long metadata subagent activity should include subagent token usage")
runner.check(localSnapshot.tasks.first { $0.id == staleDBTokenSessionID }?.tokenCount == 120000000, "recent task token count should prefer fresher rollout totals over stale database tokens")
runner.check(localSnapshot.tasks.contains { $0.id == activeToolCallSessionID && $0.status == .running }, "quiet tool calls should keep the running indicator on until a task-level completion event arrives")
runner.check(localSnapshot.tasks.first { $0.id == completedSessionID }?.status == .recent, "fresh completed session rollout should not be treated as running")
runner.check(localSnapshot.tasks.first { $0.id == completedFinalAnswerSessionID }?.status == .recent, "fresh final_answer/task_complete rollout should not be treated as running")
runner.check(localSnapshot.tasks.first { $0.id == completedLogFinalSessionID }?.status == .recent, "logs final-phase completion should clear stale running state")
runner.check(localSnapshot.tasks.first { $0.id == dbBackedSessionID }?.tokenCount == 777, "recent rollout fallback should reuse database tokens even when the database updated_at is outside the task range")
runner.check(localSnapshot.primaryPercent == 88, "local snapshot should expose the latest Codex 5h remaining quota")
runner.check(localSnapshot.secondaryPercent == 66, "local snapshot should expose the latest Codex 7d remaining quota")
runner.check(localSnapshot.primaryResetsAt == Date(timeIntervalSince1970: TimeInterval(primaryResetAt)), "local snapshot should expose the 5h reset time")
runner.check(localSnapshot.secondaryResetsAt == Date(timeIntervalSince1970: TimeInterval(secondaryResetAt)), "local snapshot should expose the 7d reset time")
let localWatchPaths = Set(localStore.rateLimitWatchPaths())
let normalizedSessionDirectory = sessionDirectory.resolvingSymlinksInPath().path
let normalizedRolloutPath = rolloutPath.resolvingSymlinksInPath().path
runner.check(localWatchPaths.contains(normalizedSessionDirectory), "local file watchers should include recent session directories so new subagents trigger refreshes")
runner.check(localWatchPaths.contains(normalizedRolloutPath), "local file watchers should keep watching recent session files for active task updates")

let mixedUsageRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("CodexPetsMixedUsage-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: mixedUsageRoot, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: mixedUsageRoot)
}
let mixedUsageStateDatabase = mixedUsageRoot.appendingPathComponent("state_5.sqlite").path
let mixedUsageLogsDatabase = mixedUsageRoot.appendingPathComponent("logs_2.sqlite").path
_ = try Shell.run("/usr/bin/sqlite3", [
    mixedUsageStateDatabase,
    """
    create table threads(
      id text,
      title text,
      tokens_used integer,
      model text,
      reasoning_effort text,
      rollout_path text,
      updated_at integer,
      archived integer default 0
    );
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    mixedUsageLogsDatabase,
    """
    create table logs(
      thread_id text,
      ts integer,
      target text,
      feedback_log_body text
    );
    """
])
let mixedUsageDirectory = mixedUsageRoot.appendingPathComponent("sessions/2026/06/14", isDirectory: true)
try FileManager.default.createDirectory(at: mixedUsageDirectory, withIntermediateDirectories: true)
let mixedUsageSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd5"
let mixedUsagePath = mixedUsageDirectory.appendingPathComponent("rollout-2026-06-14T02-20-15-\(mixedUsageSessionID).jsonl")
try #"{"timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":100}}}}"#
    .write(to: mixedUsagePath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: mixedUsagePath.path)
_ = try Shell.run("/usr/bin/sqlite3", [
    mixedUsageStateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(mixedUsageSessionID)', '日志更完整的任务', 0, 'gpt-5.5', 'high', '\(mixedUsagePath.path)', \(Int(now.timeIntervalSince1970)), 0);
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    mixedUsageLogsDatabase,
    """
    insert into logs(thread_id, ts, target, feedback_log_body)
    values('\(mixedUsageSessionID)', \(Int(now.timeIntervalSince1970)), 'codex_otel.trace_safe', 'event.kind=response.completed tool_token_count=10000');
    """
])
let mixedUsageStore = CodexUsageStore(codexDirectory: mixedUsageRoot, ripgrepCandidates: [])
runner.check(mixedUsageStore.loadUsageTotals(now: now)?.day == 10000, "local usage totals should merge logs when logs have more complete token counts than rollouts")

let logCacheRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("CodexPetsLogCache-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: logCacheRoot, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: logCacheRoot)
}
let logCacheStateDatabase = logCacheRoot.appendingPathComponent("state_5.sqlite").path
let logCacheLogsDatabase = logCacheRoot.appendingPathComponent("logs_2.sqlite").path
_ = try Shell.run("/usr/bin/sqlite3", [
    logCacheStateDatabase,
    """
    create table threads(
      id text,
      title text,
      tokens_used integer,
      model text,
      reasoning_effort text,
      rollout_path text,
      updated_at integer,
      archived integer default 0
    );
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    logCacheLogsDatabase,
    """
    create table logs(
      thread_id text,
      ts integer,
      target text,
      feedback_log_body text
    );
    """
])
let logCacheDirectory = logCacheRoot.appendingPathComponent("sessions/2026/06/14", isDirectory: true)
try FileManager.default.createDirectory(at: logCacheDirectory, withIntermediateDirectories: true)
let logCacheSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd6"
let logCachePath = logCacheDirectory.appendingPathComponent("rollout-2026-06-14T02-20-16-\(logCacheSessionID).jsonl")
try #"{"timestamp":"\#(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"仅日志统计"}]}}"#
    .write(to: logCachePath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: logCachePath.path)
_ = try Shell.run("/usr/bin/sqlite3", [
    logCacheStateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(logCacheSessionID)', '仅日志统计', 0, 'gpt-5.5', 'high', '\(logCachePath.path)', \(Int(now.timeIntervalSince1970)), 0);
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    logCacheLogsDatabase,
    """
    insert into logs(thread_id, ts, target, feedback_log_body)
    values('\(logCacheSessionID)', \(Int(now.timeIntervalSince1970)), 'codex_otel.trace_safe', 'event.kind=response.completed tool_token_count=1000');
    """
])
let logCacheStore = CodexUsageStore(codexDirectory: logCacheRoot, ripgrepCandidates: [])
runner.check(logCacheStore.loadUsageTotals(now: now)?.day == 1000, "log fallback usage should be available when rollout usage is empty")
_ = try Shell.run("/usr/bin/sqlite3", [
    logCacheLogsDatabase,
    """
    insert into logs(thread_id, ts, target, feedback_log_body)
    values('\(logCacheSessionID)', \(Int(now.timeIntervalSince1970) + 1), 'codex_otel.trace_safe', 'event.kind=response.completed tool_token_count=2000');
    """
])
runner.check(logCacheStore.loadUsageTotals(now: now.addingTimeInterval(1))?.day == 3000, "log fallback usage cache should refresh when logs database changes")

let cachedLocalSnapshot = localStore.loadSnapshot(
    includePeriodUsage: false,
    bypassFastCache: false,
    rateLimitSource: .localFilesOnly,
    taskHistoryRange: .day,
    now: now
)
runner.check(cachedLocalSnapshot.tasks.contains { $0.id == parentOnlySessionID && $0.status == .running }, "fast snapshot cache should preserve active parent task ids")
runner.check(cachedLocalSnapshot.tasks.first { $0.id == parentOnlySessionID }?.activeSubagentCount == 1, "fast snapshot cache should preserve active subagent counts")

let snapshotLogRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("CodexPetsSnapshotLogSignature-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: snapshotLogRoot, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: snapshotLogRoot)
}
let snapshotLogStateDatabase = snapshotLogRoot.appendingPathComponent("state_5.sqlite").path
let snapshotLogLogsDatabase = snapshotLogRoot.appendingPathComponent("logs_2.sqlite").path
_ = try Shell.run("/usr/bin/sqlite3", [
    snapshotLogStateDatabase,
    """
    create table threads(
      id text,
      title text,
      tokens_used integer,
      model text,
      reasoning_effort text,
      rollout_path text,
      updated_at integer,
      archived integer default 0
    );
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    snapshotLogLogsDatabase,
    """
    create table logs(
      thread_id text,
      ts integer,
      target text,
      feedback_log_body text
    );
    """
])
let snapshotLogDirectory = snapshotLogRoot.appendingPathComponent("sessions/2026/06/14", isDirectory: true)
try FileManager.default.createDirectory(at: snapshotLogDirectory, withIntermediateDirectories: true)
let snapshotLogSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd7"
let snapshotLogPath = snapshotLogDirectory.appendingPathComponent("rollout-2026-06-14T02-20-17-\(snapshotLogSessionID).jsonl")
try """
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"日志触发运行状态"}]}}
{"timestamp":"\(timestamp)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"完成"}],"phase":"final"}}
"""
    .write(to: snapshotLogPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: snapshotLogPath.path)
_ = try Shell.run("/usr/bin/sqlite3", [
    snapshotLogStateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(snapshotLogSessionID)', '日志触发运行状态', 0, 'gpt-5.5', 'high', '\(snapshotLogPath.path)', \(Int(now.timeIntervalSince1970)), 0);
    """
])
let snapshotLogStore = CodexUsageStore(codexDirectory: snapshotLogRoot, ripgrepCandidates: [])
let idleSnapshotBeforeLog = snapshotLogStore.loadSnapshot(
    includePeriodUsage: false,
    bypassFastCache: false,
    rateLimitSource: .localFilesOnly,
    taskHistoryRange: .day,
    now: now
)
runner.check(idleSnapshotBeforeLog.tasks.first { $0.id == snapshotLogSessionID }?.status == .recent, "snapshot log fixture should start as a recent task")
_ = try Shell.run("/usr/bin/sqlite3", [
    snapshotLogLogsDatabase,
    """
    insert into logs(thread_id, ts, target, feedback_log_body)
    values('\(snapshotLogSessionID)', \(Int(now.timeIntervalSince1970) + 1), 'codex_otel.trace_safe', '{"type":"event_msg","payload":{"type":"response.output_item.added"}}');
    """
])
let runningSnapshotAfterLog = snapshotLogStore.loadSnapshot(
    includePeriodUsage: false,
    bypassFastCache: false,
    rateLimitSource: .localFilesOnly,
    taskHistoryRange: .day,
    now: now.addingTimeInterval(1)
)
runner.check(
    runningSnapshotAfterLog.tasks.first { $0.id == snapshotLogSessionID }?.status == .running,
    "fast snapshot cache should invalidate when logs database activity changes"
)

let firstLocalUsageTotal = localStore.loadUsageTotals(now: now)?.day
let firstLocalUsageDisplay = firstLocalUsageTotal.map(String.init) ?? "nil"
runner.check(
    firstLocalUsageTotal == 120622065,
    "session rollout token counts should contribute to local usage totals (actual: \(firstLocalUsageDisplay))"
)
let cachedLocalUsageTotal = localStore.loadUsageTotals(now: now.addingTimeInterval(1))?.day
let cachedLocalUsageDisplay = cachedLocalUsageTotal.map(String.init) ?? "nil"
runner.check(
    cachedLocalUsageTotal == 120622065,
    "unchanged local usage totals should remain stable across cached refreshes (actual: \(cachedLocalUsageDisplay))"
)

let largeUsageRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("CodexPetsLargeUsage-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: largeUsageRoot, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: largeUsageRoot)
}
let largeUsageStateDatabase = largeUsageRoot.appendingPathComponent("state_5.sqlite").path
let largeUsageLogsDatabase = largeUsageRoot.appendingPathComponent("logs_2.sqlite").path
_ = try Shell.run("/usr/bin/sqlite3", [
    largeUsageStateDatabase,
    """
    create table threads(
      id text,
      title text,
      tokens_used integer,
      model text,
      reasoning_effort text,
      rollout_path text,
      updated_at integer,
      archived integer default 0
    );
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    largeUsageLogsDatabase,
    """
    create table logs(
      thread_id text,
      ts integer,
      target text,
      feedback_log_body text
    );
    """
])
let largeUsageDirectory = largeUsageRoot.appendingPathComponent("sessions/2026/06/14", isDirectory: true)
try FileManager.default.createDirectory(at: largeUsageDirectory, withIntermediateDirectories: true)
let largeUsageSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd4"
let largeUsagePath = largeUsageDirectory.appendingPathComponent("rollout-2026-06-14T02-20-14-\(largeUsageSessionID).jsonl")
try Data(repeating: UInt8(ascii: " "), count: 21 * 1024 * 1024).write(to: largeUsagePath)
if let handle = try? FileHandle(forWritingTo: largeUsagePath) {
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(("\n" + #"{"timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":1}}}}"# + "\n").utf8))
    try handle.close()
}
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: largeUsagePath.path)
let fakeRipgrepPath = largeUsageRoot.appendingPathComponent("fake-rg").path
try """
#!/bin/sh
/usr/bin/grep '"token_count"'
""".write(toFile: fakeRipgrepPath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeRipgrepPath)
_ = try Shell.run("/usr/bin/sqlite3", [
    largeUsageStateDatabase,
    """
    insert into threads(id, title, tokens_used, model, reasoning_effort, rollout_path, updated_at, archived)
    values('\(largeUsageSessionID)', '大文件统计任务', 777777, 'gpt-5.5', 'high', '\(largeUsagePath.path)', \(Int(now.timeIntervalSince1970)), 0);
    """
])
let largeUsageStore = CodexUsageStore(codexDirectory: largeUsageRoot, ripgrepCandidates: [fakeRipgrepPath])
runner.check(largeUsageStore.loadUsageTotals(now: now)?.day == 1, "large rollout usage totals should use exact token events when fast search is available")
let largeUsageFallbackStore = CodexUsageStore(codexDirectory: largeUsageRoot, ripgrepCandidates: [])
runner.check(largeUsageFallbackStore.loadUsageTotals(now: now)?.day == 777777, "large rollout usage totals should fall back to database tokens when fast search is unavailable")

let tokenCacheRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("CodexPetsTokenCache-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tokenCacheRoot, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: tokenCacheRoot)
}
let tokenCacheStateDatabase = tokenCacheRoot.appendingPathComponent("state_5.sqlite").path
let tokenCacheLogsDatabase = tokenCacheRoot.appendingPathComponent("logs_2.sqlite").path
_ = try Shell.run("/usr/bin/sqlite3", [
    tokenCacheStateDatabase,
    """
    create table threads(
      id text,
      title text,
      tokens_used integer,
      model text,
      reasoning_effort text,
      rollout_path text,
      updated_at integer,
      archived integer default 0
    );
    """
])
_ = try Shell.run("/usr/bin/sqlite3", [
    tokenCacheLogsDatabase,
    """
    create table logs(
      thread_id text,
      ts integer,
      target text,
      feedback_log_body text
    );
    """
])
let tokenCacheSessionDirectory = tokenCacheRoot.appendingPathComponent("sessions/2026/06/14", isDirectory: true)
try FileManager.default.createDirectory(at: tokenCacheSessionDirectory, withIntermediateDirectories: true)
let tokenCacheSessionID = "019e073a-c032-74e2-966e-b85ede0c9cd3"
let tokenCachePath = tokenCacheSessionDirectory.appendingPathComponent("rollout-2026-06-14T02-20-13-\(tokenCacheSessionID).jsonl")
let firstTokenLine = #"{"timestamp":"\#(timestamp)","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"无尾换行 token"}]}}"# + "\n" +
    #"{"timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":100}}}}"#
try firstTokenLine.write(to: tokenCachePath, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: tokenCachePath.path)
let tokenCacheStore = CodexUsageStore(codexDirectory: tokenCacheRoot)
let firstTokenSnapshot = tokenCacheStore.loadSnapshot(
    includePeriodUsage: false,
    bypassFastCache: true,
    rateLimitSource: .localFilesOnly,
    taskHistoryRange: .day,
    now: now
)
runner.check(firstTokenSnapshot.tasks.first { $0.id == tokenCacheSessionID }?.tokenCount == 100, "initial no-newline token event should be counted once")
let secondTokenLine = "\n" + #"{"timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":50}}}}"# + "\n"
if let handle = try? FileHandle(forWritingTo: tokenCachePath) {
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(secondTokenLine.utf8))
    try handle.close()
}
try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(1)], ofItemAtPath: tokenCachePath.path)
let secondTokenSnapshot = tokenCacheStore.loadSnapshot(
    includePeriodUsage: false,
    bypassFastCache: true,
    rateLimitSource: .localFilesOnly,
    taskHistoryRange: .day,
    now: now.addingTimeInterval(1)
)
runner.check(secondTokenSnapshot.tasks.first { $0.id == tokenCacheSessionID }?.tokenCount == 150, "appending after an initially unterminated token line should not double count the pending line")

if runner.failures > 0 {
    FileHandle.standardError.write(Data("\(runner.failures) regression test(s) failed\n".utf8))
    exit(1)
}

print("All regression tests passed")
