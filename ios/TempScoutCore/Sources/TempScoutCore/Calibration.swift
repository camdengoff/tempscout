import Foundation

/// One known light: what the camera said (`m`) and the truth (`t`), both in mired.
public struct CalPoint: Codable, Equatable {
    public var m: Double
    public var t: Double
    public init(m: Double, t: Double) { self.m = m; self.t = t }
}

/// true = a * measured + b   (all in mired)
public struct CalFit: Equatable {
    public var a: Double
    public var b: Double
    public var n: Int
    public init(a: Double, b: Double, n: Int) { self.a = a; self.b = b; self.n = n }
}

/// Calibration curve. With one known light it is a plain shift; with two or more it also fits a slope,
/// which corrects for the camera squashing the range of colours.
public enum Calibration {
    public static let maxPoints = 4

    public static func fit(_ points: [CalPoint], legacyShift: Double = 0) -> CalFit {
        let n = points.count
        if n == 0 { return CalFit(a: 1, b: legacyShift, n: 0) }
        let count = Double(n)
        let mx = points.reduce(0) { $0 + $1.m } / count
        let my = points.reduce(0) { $0 + $1.t } / count
        let sxx = points.reduce(0) { $0 + ($1.m - mx) * ($1.m - mx) }
        let sxy = points.reduce(0) { $0 + ($1.m - mx) * ($1.t - my) }
        if n == 1 || sxx < 25 { return CalFit(a: 1, b: my - mx, n: n) }   // lights too similar to fit a slope
        let a = max(0.5, min(2, sxy / sxx))
        return CalFit(a: a, b: my - a * mx, n: n)
    }

    /// When the camera's white balance is locked at `lockedKelvin`, light of exactly that temperature
    /// renders neutral grey (which reads as 6504K), so readings are shifted by this many mired.
    public static func wbOffsetMired(lockedKelvin: Double) -> Double {
        ColorMath.mired(lockedKelvin) - ColorMath.mired(ColorMath.d65Kelvin)
    }

    /// The camera's raw Kelvin -> true mired.
    public static func calibratedMired(rawKelvin: Double, wbOffset: Double, fit: CalFit) -> Double {
        max(80, min(700, fit.a * (ColorMath.mired(rawKelvin) + wbOffset) + fit.b))
    }

    /// Adds a point. Re-measuring a light you already added replaces that point; at most four are kept.
    public static func adding(_ point: CalPoint, to points: [CalPoint]) -> [CalPoint] {
        var out = points.filter { abs($0.t - point.t) > 8 }
        out.append(point)
        if out.count > maxPoints { out.removeFirst() }
        return out
    }
}
