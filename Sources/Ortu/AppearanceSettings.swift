import Foundation

struct AppearanceSettings: Equatable, Sendable {
    static let defaultOpacity = 0.92
    static let defaultDrop = 0.56
    static let defaultWidth = 0.96
    static let defaultDimAmount = 0.16

    static let opacityRange = 0.35 ... 1.0
    static let dropRange = 0.20 ... 0.85
    static let widthRange = 0.20 ... 1.0
    static let dimAmountRange = 0.0 ... 1.0

    var opacity: Double
    var drop: Double
    var width: Double
    var dimAmount: Double

    init(
        opacity: Double = Self.defaultOpacity,
        drop: Double = Self.defaultDrop,
        width: Double = Self.defaultWidth,
        dimAmount: Double = Self.defaultDimAmount
    ) {
        self.opacity = Self.normalizeOpacity(opacity)
        self.drop = Self.normalizeDrop(drop)
        self.width = Self.normalizeWidth(width)
        self.dimAmount = Self.normalizeDimAmount(dimAmount)
    }

    static func normalizeOpacity(_ value: Double) -> Double {
        OverlayLayout.clamp(value, to: opacityRange)
    }

    static func normalizeDrop(_ value: Double) -> Double {
        OverlayLayout.clamp(value, to: dropRange)
    }

    static func normalizeWidth(_ value: Double) -> Double {
        OverlayLayout.clamp(value, to: widthRange)
    }

    static func normalizeDimAmount(_ value: Double) -> Double {
        OverlayLayout.clamp(value, to: dimAmountRange)
    }
}
