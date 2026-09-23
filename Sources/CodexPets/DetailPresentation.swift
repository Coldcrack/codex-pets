import Foundation
import CoreGraphics

enum DetailPresentationPhase: Equatable {
    case hidden
    case revealing
    case visible
    case hiding

    var showsContent: Bool {
        self == .visible
    }
}

struct DetailTransitionState {
    private(set) var phase: DetailPresentationPhase = .hidden
    private(set) var generation: UInt = 0

    mutating func begin(expanded: Bool) -> UInt {
        generation &+= 1
        phase = expanded ? .revealing : .hiding
        return generation
    }

    func isCurrent(_ candidate: UInt) -> Bool {
        generation == candidate
    }

    mutating func completeShow(generation candidate: UInt) -> Bool {
        guard isCurrent(candidate), phase == .revealing else {
            return false
        }
        phase = .visible
        return true
    }

    mutating func completeHide(generation candidate: UInt) -> Bool {
        guard isCurrent(candidate), phase == .hiding else {
            return false
        }
        phase = .hidden
        return true
    }
}

struct DetailWindowFrames: Equatable {
    let collapsed: CGRect
    let expanded: CGRect
}

enum DetailWindowFrameCalculator {
    static func calculate(
        screenFrame: CGRect,
        layoutWidth: CGFloat,
        collapsedHeight: CGFloat,
        detailHeight: CGFloat,
        overlap: CGFloat
    ) -> DetailWindowFrames {
        let maxY = screenFrame.maxY - collapsedHeight + overlap
        let x = screenFrame.midX - layoutWidth / 2

        return DetailWindowFrames(
            collapsed: CGRect(
                x: x,
                y: maxY - overlap,
                width: layoutWidth,
                height: overlap
            ),
            expanded: CGRect(
                x: x,
                y: maxY - detailHeight,
                width: layoutWidth,
                height: detailHeight
            )
        )
    }

    static func calculateAbovePet(
        screenFrame: CGRect,
        petFrame: CGRect,
        detailWidth: CGFloat,
        detailHeight: CGFloat,
        overlap: CGFloat,
        gap: CGFloat
    ) -> DetailWindowFrames {
        let x = min(
            screenFrame.maxX - detailWidth - PetMetrics.screenMargin,
            max(screenFrame.minX + PetMetrics.screenMargin, petFrame.maxX - detailWidth)
        )
        let y = min(
            petFrame.maxY + gap,
            screenFrame.maxY - detailHeight - PetMetrics.screenMargin
        )

        return DetailWindowFrames(
            collapsed: CGRect(x: x, y: y, width: detailWidth, height: overlap),
            expanded: CGRect(x: x, y: y, width: detailWidth, height: detailHeight)
        )
    }

    static func calculateBelowMenuBar(
        screenFrame: CGRect,
        anchorFrame: CGRect,
        detailWidth: CGFloat,
        detailHeight: CGFloat,
        overlap: CGFloat,
        gap: CGFloat
    ) -> DetailWindowFrames {
        let x = min(
            screenFrame.maxX - detailWidth - PetMetrics.screenMargin,
            max(
                screenFrame.minX + PetMetrics.screenMargin,
                anchorFrame.midX - detailWidth / 2
            )
        )
        let top = min(anchorFrame.minY - gap, screenFrame.maxY - gap)
        let y = max(screenFrame.minY + PetMetrics.screenMargin, top - detailHeight)

        return DetailWindowFrames(
            collapsed: CGRect(
                x: x,
                y: y + detailHeight - overlap,
                width: detailWidth,
                height: overlap
            ),
            expanded: CGRect(x: x, y: y, width: detailWidth, height: detailHeight)
        )
    }
}

enum DetailAnimationTiming {
    static let revealDuration: TimeInterval = 0.26
    static let contentDelay: TimeInterval = 0.06
    static let contentDuration: TimeInterval = 0.14
    static let hideContentDuration: TimeInterval = 0.10
    static let hideShellDelay: TimeInterval = 0.04
    static let hideDuration: TimeInterval = 0.20
}
