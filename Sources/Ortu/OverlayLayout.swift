import CoreGraphics
import Foundation

struct OverlayLayout: Sendable {
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func foldProgress(dragDistance: Double, threshold: Double) -> Double {
        guard threshold > 0 else { return 1 }
        return clamp(dragDistance / threshold, to: 0 ... 1)
    }

    static func dismissalState(progress: Double) -> OverlayDismissalState {
        let progress = clamp(progress, to: 0 ... 1)
        let smoothProgress = progress * progress * (3 - 2 * progress)
        return OverlayDismissalState(
            foldProgress: 1 - pow(1 - progress, 2),
            backgroundVisibility: 1 - smoothProgress,
            coverVisibility: 1 - pow(progress, 3)
        )
    }

    static func backgroundVisibility(foldProgress: Double) -> Double {
        let progress = clamp(foldProgress, to: 0 ... 1)
        return 1 - progress * progress * (3 - 2 * progress)
    }

    static func coverRect(
        in bounds: CGRect,
        imageSize: CGSize?,
        width: Double,
        drop: Double,
        foldProgress: Double
    ) -> CGRect {
        let maximumWidth = bounds.width * clamp(width, to: 0 ... 1)
        let maximumHeight = bounds.height * clamp(drop, to: 0 ... 1)

        // Width always wins so a wide external display stays covered. Drop is
        // only a height ceiling; it must not enlarge a naturally shallow motif.
        let naturalHeight: CGFloat
        if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            naturalHeight = maximumWidth * imageSize.height / imageSize.width
        } else {
            naturalHeight = maximumHeight
        }
        let fittedSize = CGSize(
            width: maximumWidth,
            height: min(maximumHeight, naturalHeight) * (1 - clamp(foldProgress, to: 0 ... 1))
        )
        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: max(bounds.minY, bounds.maxY - fittedSize.height),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

struct OverlayDismissalState: Equatable, Sendable {
    let foldProgress: Double
    let backgroundVisibility: Double
    let coverVisibility: Double
}

struct OverlayAppearance: Equatable, Sendable {
    var opacity: Double
    var drop: Double
    var width: Double
    var dimAmount: Double
    var textureURL: URL?
    var tintColor: RGBAColor?
}

enum DisplayScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case primary
    case pointer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.text("display.all.title")
        case .primary: L10n.text("display.primary.title")
        case .pointer: L10n.text("display.pointer.title")
        }
    }

    var detail: String {
        switch self {
        case .all: L10n.text("display.all.detail")
        case .primary: L10n.text("display.primary.detail")
        case .pointer: L10n.text("display.pointer.detail")
        }
    }
}

struct RGBAColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = OverlayLayout.clamp(red, to: 0 ... 1)
        self.green = OverlayLayout.clamp(green, to: 0 ... 1)
        self.blue = OverlayLayout.clamp(blue, to: 0 ... 1)
        self.alpha = OverlayLayout.clamp(alpha, to: 0 ... 1)
    }

    init?(hexRGB: String) {
        let value = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    var hexRGB: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}
