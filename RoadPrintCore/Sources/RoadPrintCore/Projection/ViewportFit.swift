import Foundation

/// A point in projected metres or, after fitting, screen points.
public struct PlanePoint: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Insets measured in screen points.
public struct ViewportInsets: Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double
    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}

/// Uniform projected-metre to screen-point transform; screen y increases downwards.
public struct ViewportFit: Sendable, Equatable {
    public let scale: Double
    public let translation: PlanePoint

    /// Fits a projected rectangle, expanding its larger dimension to at least
    /// `minimumSpanMeters`. Returns nil for invalid or unavailable view dimensions.
    public init?(min: PlanePoint, max: PlanePoint, width: Double, height: Double,
                 insets: ViewportInsets = ViewportInsets(), minimumSpanMeters: Double = 50_000,
                 maximumScale: Double = .greatestFiniteMagnitude) {
        let values = [min.x, min.y, max.x, max.y, width, height, insets.top, insets.left,
                      insets.bottom, insets.right, minimumSpanMeters, maximumScale]
        guard values.allSatisfy(\.isFinite), max.x >= min.x, max.y >= min.y,
              insets.top >= 0, insets.left >= 0, insets.bottom >= 0, insets.right >= 0,
              minimumSpanMeters > 0, maximumScale > 0 else { return nil }
        let availableWidth = width - insets.left - insets.right
        let availableHeight = height - insets.top - insets.bottom
        guard availableWidth > 0, availableHeight > 0 else { return nil }
        let dx = max.x - min.x, dy = max.y - min.y
        guard dx.isFinite, dy.isFinite else { return nil }
        // Preserve the route's aspect while expanding its larger span.
        let span = Swift.max(dx, dy)
        let fitWidth = span == 0 ? minimumSpanMeters : (span < minimumSpanMeters ? minimumSpanMeters * (dx / span) : dx)
        let fitHeight = span == 0 ? minimumSpanMeters : (span < minimumSpanMeters ? minimumSpanMeters * (dy / span) : dy)
        let fittedScale = Swift.min(maximumScale, availableWidth / fitWidth, availableHeight / fitHeight)
        let centerX = min.x / 2 + max.x / 2, centerY = min.y / 2 + max.y / 2
        let tx = insets.left + availableWidth / 2 - fittedScale * centerX
        let ty = insets.top + availableHeight / 2 + fittedScale * centerY
        guard fittedScale.isFinite, fittedScale > 0, tx.isFinite, ty.isFinite else { return nil }
        scale = fittedScale
        translation = PlanePoint(x: tx, y: ty)
    }

    public func apply(_ point: PlanePoint) -> PlanePoint {
        PlanePoint(x: point.x * scale + translation.x, y: -point.y * scale + translation.y)
    }
}
