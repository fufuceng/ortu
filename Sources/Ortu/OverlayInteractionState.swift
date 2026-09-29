import CoreGraphics
import Foundation

enum OverlayReleaseAction: Equatable, Sendable {
    case dismiss
    case settle
}

struct OverlayInteractionState: Equatable, Sendable {
    private(set) var dragStart: CGPoint?
    private(set) var grabPoint: CGPoint?
    private(set) var dragOffset = CGSize.zero
    private(set) var foldProgress = 0.0
    private(set) var backgroundVisibility = 1.0
    private(set) var coverVisibility = 1.0

    mutating func reset() {
        dragStart = nil
        grabPoint = nil
        dragOffset = .zero
        foldProgress = 0
        backgroundVisibility = 1
        coverVisibility = 1
    }

    @discardableResult
    mutating func beginDrag(at point: CGPoint, coverRect: CGRect) -> Bool {
        guard coverRect.contains(point) else { return false }
        dragStart = point
        grabPoint = point
        dragOffset = .zero
        return true
    }

    mutating func updateDrag(to point: CGPoint, threshold: Double) {
        guard let dragStart else { return }
        dragOffset = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
        foldProgress = OverlayLayout.foldProgress(
            dragDistance: max(0, point.y - dragStart.y),
            threshold: threshold
        )
        backgroundVisibility = OverlayLayout.backgroundVisibility(foldProgress: foldProgress)
    }

    mutating func endDrag(dismissalThreshold: Double = 0.42) -> OverlayReleaseAction {
        dragStart = nil
        return foldProgress >= dismissalThreshold ? .dismiss : .settle
    }

    mutating func applyEntrance(progress: Double) {
        let progress = OverlayLayout.clamp(progress, to: 0 ... 1)
        let eased = 1 - pow(1 - progress, 3)
        foldProgress = 1 - eased
        backgroundVisibility = eased
        coverVisibility = 1
    }

    mutating func applyDismissal(
        progress: Double,
        initialFoldProgress: Double,
        initialBackgroundVisibility: Double,
        initialCoverVisibility: Double
    ) {
        let dismissal = OverlayLayout.dismissalState(progress: progress)
        foldProgress = initialFoldProgress + (1 - initialFoldProgress) * dismissal.foldProgress
        backgroundVisibility = initialBackgroundVisibility * dismissal.backgroundVisibility
        coverVisibility = initialCoverVisibility * dismissal.coverVisibility
    }

    mutating func applySettlement(
        progress: Double,
        initialOffset: CGSize,
        initialFoldProgress: Double,
        initialBackgroundVisibility: Double
    ) {
        let progress = OverlayLayout.clamp(progress, to: 0 ... 1)
        let spring = exp(-5.5 * progress) * cos(9.0 * progress)
        dragOffset = CGSize(width: initialOffset.width * spring, height: initialOffset.height * spring)
        foldProgress = max(0, initialFoldProgress * (1 - progress))
        backgroundVisibility = initialBackgroundVisibility + (1 - initialBackgroundVisibility) * progress
    }

    mutating func finishTransition() {
        reset()
    }

    mutating func finishDismissal() {
        dragStart = nil
        grabPoint = nil
        dragOffset = .zero
        foldProgress = 1
        backgroundVisibility = 0
        coverVisibility = 0
    }
}
