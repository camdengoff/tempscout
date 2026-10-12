import Foundation

/// One colour-temperature reading.
public struct Reading: Equatable {
    /// 0-255 sRGB colour that was measured
    public var rgb: RGB
    /// Calibrated colour temperature in mired (nil if too dark)
    public var mired: Double?
    /// 0...1
    public var luminance: Double
    /// Percent, positive = toward green
    public var tint: Double
    /// For a "Measure" average: how much the 30 frames disagreed, in Kelvin
    public var spreadK: Int?

    public var kelvin: Double? { mired.map { 1e6 / $0 } }
    /// Rounded to 50K: the camera is not good to 10K, so don't pretend it is.
    public var displayKelvin: Int? { kelvin.map { Int(($0 / 50).rounded() * 50) } }
}

/// Is the live reading trustworthy?
public enum MeterQuality: Equatable {
    case waiting
    case tooBright
    case tooDark
    case moving
    case settling
    case steady
    case measured(spreadK: Int)
    case noisy(spreadK: Int)
}

/// Takes the average colour of the measure square (linear light, 0-1) about ten times a second and turns it
/// into steady readings: smoothing, a quality hint, and the 3 second "Measure" average.
public final class MeterEngine {
    public static let framesPerMeasure = 30

    /// nil = automatic white balance. Otherwise the Kelvin the camera's white balance is locked at.
    public var lockedKelvin: Double?
    public var calPoints: [CalPoint] = []
    public var legacyShift: Double = 0

    public private(set) var live: Reading?
    public private(set) var held: Reading?
    public private(set) var quality: MeterQuality = .waiting
    /// 0...framesPerMeasure while measuring, nil otherwise
    public private(set) var progress: Int?

    private var smoothed: RGB?
    private var heldLinear: RGB?
    private var recentMired: [Double] = []
    private var sum = RGB(r: 0, g: 0, b: 0)
    private var sampledMired: [Double] = []

    public init() {}

    public var isHeld: Bool { held != nil }
    public var current: Reading? { held ?? live }

    /// Colour (linear light) -> reading, using the current white balance lock and calibration.
    public func reading(fromLinear lin: RGB) -> Reading {
        let r = ColorMath.toSRGB(lin.r), g = ColorMath.toSRGB(lin.g), b = ColorMath.toSRGB(lin.b)
        var m: Double?
        if let raw = ColorMath.rgbToKelvin(r: r, g: g, b: b) {
            m = Calibration.calibratedMired(rawKelvin: raw, wbOffset: wbOffset,
                                            fit: Calibration.fit(calPoints, legacyShift: legacyShift))
        }
        return Reading(rgb: RGB(r: r, g: g, b: b), mired: m,
                       luminance: ColorMath.luminance(r: r, g: g, b: b),
                       tint: ColorMath.tint(r: r, g: g, b: b), spreadK: nil)
    }

    private var wbOffset: Double {
        lockedKelvin.map { Calibration.wbOffsetMired(lockedKelvin: $0) } ?? 0
    }

    /// What the camera said for the current colour, before calibration: used when adding a calibration point.
    public func measuredMiredForCalibration() -> Double? {
        guard let c = current,
              let raw = ColorMath.rgbToKelvin(r: c.rgb.r, g: c.rgb.g, b: c.rgb.b) else { return nil }
        return ColorMath.mired(raw) + wbOffset
    }

    /// What the camera says for the current colour with no calibration applied (white balance lock still accounted for).
    public func uncalibratedKelvin() -> Double? {
        measuredMiredForCalibration().map { 1e6 / $0 }
    }

    public func ingest(linear lin: RGB, clipped: Bool) {
        if held != nil { return }
        let frame = reading(fromLinear: lin)
        if let m = frame.mired {
            recentMired.append(m)
            if recentMired.count > 10 { recentMired.removeFirst() }
        }

        if let done = progress {                      // "Measure": collect frames, then finish
            sum.r += lin.r; sum.g += lin.g; sum.b += lin.b
            if let m = frame.mired { sampledMired.append(m) }
            let n = done + 1
            progress = n
            if n >= Self.framesPerMeasure {
                finishMeasuring(frames: n)
                return
            }
        }

        if var s = smoothed {
            s.r += (lin.r - s.r) * 0.25; s.g += (lin.g - s.g) * 0.25; s.b += (lin.b - s.b) * 0.25
            smoothed = s
        } else {
            smoothed = lin
        }
        let r = reading(fromLinear: smoothed!)
        live = r

        if clipped || r.luminance > 0.95 { quality = .tooBright }
        else if r.luminance < 0.08 { quality = .tooDark }
        else if recentMired.count >= 10 && Self.standardDeviation(recentMired) > 15 { quality = .moving }
        else if recentMired.count >= 10 && Self.standardDeviation(recentMired) > 6 { quality = .settling }
        else { quality = .steady }
    }

    private func finishMeasuring(frames n: Int) {
        let count = Double(n)
        let avg = RGB(r: sum.r / count, g: sum.g / count, b: sum.b / count)
        var result = reading(fromLinear: avg)
        var spread = 0
        if let k = result.kelvin, let m = result.mired, !sampledMired.isEmpty {
            let sdM = Self.standardDeviation(sampledMired)
            spread = Int((abs(k - 1e6 / (m + sdM)) / 10).rounded()) * 10
        }
        result.spreadK = spread
        smoothed = avg
        heldLinear = avg
        held = result
        progress = nil
        quality = spread > 300 ? .noisy(spreadK: spread) : .measured(spreadK: spread)
    }

    /// Start the 3 second average.
    public func startMeasuring() {
        guard held == nil, progress == nil else { return }
        sum = RGB(r: 0, g: 0, b: 0)
        sampledMired = []
        progress = 0
    }

    /// Re-work the current reading with the latest calibration (after a point is added or removed).
    public func refresh() {
        if let lin = heldLinear, var h = held {
            let spread = h.spreadK
            h = reading(fromLinear: lin)
            h.spreadK = spread
            held = h
        } else if let s = smoothed {
            live = reading(fromLinear: s)
        }
    }

    /// Go back to live readings.
    public func resume() {
        held = nil
        heldLinear = nil
        progress = nil
        recentMired = []
        quality = .waiting
    }

    public static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
