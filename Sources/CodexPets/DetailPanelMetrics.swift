import CoreGraphics

struct DetailPanelLayout: Equatable {
    let sideSectionWidth: CGFloat
    let contentWidth: CGFloat
    let collapsedHeight: CGFloat

    var width: CGFloat {
        sideSectionWidth * 2 + contentWidth
    }
}

enum PetMetrics {
    static let width: CGFloat = 236
    static let height: CGFloat = 226
    static let screenMargin: CGFloat = 18
    static let detailGap: CGFloat = 8
}

enum DetailPanelMetrics {
    static let sideSectionWidth: CGFloat = 52
    static let contentWidth: CGFloat = 244
    static let collapsedHeight: CGFloat = 38
    static let detailHeaderHeight: CGFloat = 22
    static let detailTopPadding: CGFloat = 54
    static let detailBottomPadding: CGFloat = 14
    static let detailOverlap: CGFloat = 18
    static let quotaResetTopMargin: CGFloat = 7
    static let quotaResetTextHeight: CGFloat = 20
    static let quotaResetHeaderGap: CGFloat = 8
    static let minimumDetailHeight: CGFloat = 250
    static let visibleTaskRows = 4

    static var detailHeight: CGFloat {
        detailHeight(taskRows: 2, showsPeriodUsage: true)
    }

    static var width: CGFloat {
        sideSectionWidth * 2 + contentWidth
    }

    static func detailCoveredTopHeight(
        safeAreaTop: CGFloat,
        collapsedHeight: CGFloat = collapsedHeight
    ) -> CGFloat {
        let detailTopDistanceFromScreenTop = collapsedHeight - detailOverlap
        return max(detailOverlap, safeAreaTop - detailTopDistanceFromScreenTop, 0)
    }

    static func quotaResetTopPadding(
        safeAreaTop: CGFloat,
        collapsedHeight: CGFloat = collapsedHeight
    ) -> CGFloat {
        detailCoveredTopHeight(safeAreaTop: safeAreaTop, collapsedHeight: collapsedHeight) + quotaResetTopMargin
    }

    static func detailContentTopPadding(
        safeAreaTop: CGFloat,
        collapsedHeight: CGFloat = collapsedHeight
    ) -> CGFloat {
        max(
            detailTopPadding,
            quotaResetTopPadding(safeAreaTop: safeAreaTop, collapsedHeight: collapsedHeight) + quotaResetTextHeight + quotaResetHeaderGap
        )
    }

    static func detailHeight(
        taskRows: Int,
        showsPeriodUsage: Bool,
        topPadding: CGFloat = detailTopPadding
    ) -> CGFloat {
        let rows = max(1, min(visibleTaskRows, taskRows))
        let taskStackHeight = CGFloat(rows) * 46 + CGFloat(max(0, rows - 1)) * 6
        let periodHeight: CGFloat = showsPeriodUsage ? 8 + 41 : 0
        let contentHeight = topPadding
            + detailHeaderHeight
            + 10
            + taskStackHeight
            + periodHeight
            + detailBottomPadding
        return max(minimumDetailHeight, ceil(contentHeight))
    }
}
