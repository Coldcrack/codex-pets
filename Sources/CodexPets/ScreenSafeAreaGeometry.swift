import AppKit

enum ScreenSafeAreaGeometry {
    static func topSafeInset(for screen: NSScreen?) -> CGFloat {
        guard let screen else {
            return 0
        }
        return topSafeInset(
            screen.safeAreaInsets.top,
            leftAreaHeight: screen.auxiliaryTopLeftArea?.height ?? 0,
            rightAreaHeight: screen.auxiliaryTopRightArea?.height ?? 0
        )
    }

    static func topSafeInset(
        _ safeAreaTop: CGFloat,
        leftAreaHeight: CGFloat,
        rightAreaHeight: CGFloat
    ) -> CGFloat {
        max(safeAreaTop, leftAreaHeight, rightAreaHeight)
    }
}
