import Foundation
import Testing
@testable import CodexPets

@Test
func queuedOneShotRefreshIsNotDropped() {
    var queue = UsageRefreshQueue()

    let started = queue.request(scheduleNext: false)
    let queued = queue.request(scheduleNext: false)
    #expect(started)
    #expect(!queued)
    #expect(queue.hasPendingRequest)
    #expect(queue.complete() == .schedulePending(scheduleNext: false))

    let restarted = queue.request(scheduleNext: false)
    #expect(restarted)
    #expect(queue.complete() == .finished(scheduleNext: false))
}

@Test
func queuedRefreshPreservesPeriodicSchedulingIntent() {
    var queue = UsageRefreshQueue()

    let started = queue.request(scheduleNext: false)
    let queued = queue.request(scheduleNext: true)
    #expect(started)
    #expect(!queued)
    #expect(queue.complete() == .schedulePending(scheduleNext: true))
}

@Test
func cancellingPendingRefreshKeepsActiveRefreshValid() {
    var queue = UsageRefreshQueue()

    let started = queue.request(scheduleNext: true)
    let queued = queue.request(scheduleNext: false)
    #expect(started)
    #expect(!queued)
    queue.cancelPending()
    #expect(queue.complete() == .finished(scheduleNext: true))
}

@Test
func partialTaskCompletionIsDetectedWhileAnotherTaskRuns() {
    let now = Date(timeIntervalSince1970: 10_000)
    let first = task(id: "first", status: .running, now: now)
    let second = task(id: "second", status: .running, now: now)
    let completedFirst = task(id: "first", status: .recent, now: now)

    let completed = TaskCompletionDetector.completedRunningTaskIDs(
        previous: [first, second],
        current: [completedFirst, second]
    )

    #expect(completed == Set(["first"]))
}

@Test
func usageFailureStateDisplaysUnknownUntilARealZeroLoads() {
    #expect(PeriodUsageDisplay.text(tokens: 0, hasLoaded: false) == "--")
    #expect(PeriodUsageDisplay.text(tokens: 0, hasLoaded: true) == "0")
}

@Test
func failedUsageLoadDoesNotBecomeASuccessfulZero() {
    var state = PeriodUsageLoadState()
    let firstAttempt = Date(timeIntervalSince1970: 1_000)

    let firstResult = state.record(nil, completedAt: firstAttempt)
    #expect(!firstResult)
    #expect(!state.hasSuccessfulValue)
    #expect(state.lastSuccessfulAt == nil)
    #expect(state.consecutiveFailures == 1)

    let successfulAttempt = Date(timeIntervalSince1970: 2_000)
    let successfulResult = state.record(
        PeriodUsage(day: 0, week: 0, month: 0),
        completedAt: successfulAttempt
    )
    #expect(successfulResult)
    #expect(state.hasSuccessfulValue)
    #expect(state.lastSuccessfulAt == successfulAttempt)
    #expect(state.consecutiveFailures == 0)

    let laterFailure = state.record(
        nil,
        completedAt: Date(timeIntervalSince1970: 3_000)
    )
    #expect(!laterFailure)
    #expect(state.hasSuccessfulValue)
    #expect(state.lastSuccessfulAt == successfulAttempt)
}

@Test
func usageFailureRetriesAreBoundedAndBackedOff() {
    #expect(UsageRefreshCadence.maximumFailureRetries == 3)
    #expect(UsageRefreshCadence.failureRetryDelay(consecutiveFailures: 1) == 5)
    #expect(UsageRefreshCadence.failureRetryDelay(consecutiveFailures: 2) == 15)
    #expect(UsageRefreshCadence.failureRetryDelay(consecutiveFailures: 3) == 30)
}

@Test
func taskDetailUsesOneDynamicSource() {
    let task = task(
        id: "dynamic",
        status: .recent,
        now: Date(timeIntervalSince1970: 1_000)
    )

    #expect(
        task.displayDetail(now: Date(timeIntervalSince1970: 8_200))
            == "gpt-5.6 · 超高推理 · 2小时前"
    )
}

@Test
func systemActivityRefreshUsesAVisibleDebounceWindow() {
    #expect(SystemActivityRefreshCadence.debounceDelay == 1)
}

@Test
func menuBarQuotaUsesExistingFiveHourAndWeeklyWindows() {
    var snapshot = UsageSnapshot.empty
    snapshot.rateLimitWindows = [
        UsageQuotaWindow(id: "weekly", shortLabel: "7d", remainingPercent: 81, resetsAt: nil),
        UsageQuotaWindow(id: "primary", shortLabel: "5h", remainingPercent: 54, resetsAt: nil)
    ]

    let quota = MenuBarQuotaStatus(snapshot: snapshot)

    #expect(quota.fiveHourPercent == 54)
    #expect(quota.weeklyPercent == 81)
}

@Test
func menuBarQuotaSupportsLegacySnapshotFields() {
    var snapshot = UsageSnapshot.empty
    snapshot.primaryPercent = 63
    snapshot.secondaryPercent = 82

    let quota = MenuBarQuotaStatus(snapshot: snapshot)

    #expect(quota.fiveHourPercent == 63)
    #expect(quota.weeklyPercent == 82)
}

@Test
func menuBarLayoutPreservesVisibleAndHiddenOrder() {
    let layout = MenuBarLayout(
        visibleItems: [.weekly, .pet],
        hiddenItems: [.fiveHour]
    )

    #expect(layout.visibleItems == [.weekly, .pet])
    #expect(layout.hiddenItems == [.fiveHour])
}

@Test
func menuBarLayoutAlwaysKeepsAVisibleRecoveryItem() {
    let layout = MenuBarLayout(
        visibleItems: [],
        hiddenItems: [.pet, .fiveHour, .weekly]
    )

    #expect(layout.visibleItems == [.pet])
    #expect(layout.hiddenItems == [.fiveHour, .weekly])
}

@Test
func menuBarDetailFrameAnchorsBelowStatusItemAndStaysOnScreen() {
    let frames = DetailWindowFrameCalculator.calculateBelowMenuBar(
        screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
        anchorFrame: CGRect(x: 1_250, y: 875, width: 100, height: 25),
        detailWidth: 368,
        detailHeight: 520,
        overlap: 18,
        gap: 6
    )

    #expect(frames.expanded.maxY == 869)
    #expect(frames.expanded.maxX <= 1_440 - PetMetrics.screenMargin)
    #expect(frames.collapsed.maxY == frames.expanded.maxY)
}

private func task(id: String, status: TaskStatus, now: Date) -> CodexTask {
    CodexTask(
        id: id,
        title: id,
        status: status,
        detailPrefix: "gpt-5.6 · 超高推理",
        tokenCount: 1,
        updatedAt: now
    )
}
