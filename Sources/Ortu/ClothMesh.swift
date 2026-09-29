import CoreGraphics
import Foundation

struct ClothMesh: Sendable {
    struct Triangle: Sendable {
        let first: CGPoint
        let second: CGPoint
        let third: CGPoint
    }

    static func displacedPoint(
        _ point: CGPoint,
        in coverRect: CGRect,
        grabPoint: CGPoint,
        dragOffset: CGSize
    ) -> CGPoint {
        guard coverRect.width > 0, coverRect.height > 0 else { return point }

        let horizontalDistance = (point.x - grabPoint.x) / coverRect.width
        let verticalDistance = (point.y - grabPoint.y) / coverRect.height
        let distanceSquared = horizontalDistance * horizontalDistance + verticalDistance * verticalDistance
        let localFollow = exp(-distanceSquared * 8.0)

        // The top seam remains attached. The rest of the cloth follows the hand,
        // with a small global pull so the material moves as one connected piece.
        let depth = max(0, min(1, (coverRect.maxY - point.y) / coverRect.height))
        let seamAnchor = sin(depth * .pi / 2)
        let influence = seamAnchor * (0.16 + 0.84 * localFollow)

        return CGPoint(
            x: point.x + dragOffset.width * influence,
            y: point.y + dragOffset.height * influence
        )
    }

    static func affineTransform(from source: Triangle, to destination: Triangle) -> CGAffineTransform? {
        let sourceBasis = CGAffineTransform(
            a: source.second.x - source.first.x,
            b: source.second.y - source.first.y,
            c: source.third.x - source.first.x,
            d: source.third.y - source.first.y,
            tx: source.first.x,
            ty: source.first.y
        )
        guard abs(sourceBasis.determinant) > 0.000_001 else { return nil }

        let destinationBasis = CGAffineTransform(
            a: destination.second.x - destination.first.x,
            b: destination.second.y - destination.first.y,
            c: destination.third.x - destination.first.x,
            d: destination.third.y - destination.first.y,
            tx: destination.first.x,
            ty: destination.first.y
        )
        return sourceBasis.inverted().concatenating(destinationBasis)
    }
}

private extension CGAffineTransform {
    var determinant: CGFloat { a * d - b * c }
}
