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

    // "Card" mode: the camera itself reports the colour temperature (Apple's per-device calibration of its
    // white balance gains), so we smooth and average that number instead of working it out from the picture.
    private var usingCard = false
    private var cardRawMired: Double?          // smoothed, before calibration
    private var cardTint = 0.0
    private var heldCardRawMired: Double?
    private var sumRawMired = 0.0
    private var sumTint = 0.0
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
        if usingCard { return heldCardRawMired ?? cardRawMired }
        guard let c = current,
              let raw = ColorMath.rgbToKelvin(r: c.rgb.r, g: c.rgb.g, b: c.rgb.b) else { return nil }
        return ColorMath.mired(raw) + wbOffset
    }

    /// Card mode. `kelvin` and `tintPercent` come from the camera's own white balance calibration once it has been
    /// adjusted until the card in the measure square looks neutral. `neutralError` says how far from neutral the card
    /// still looks (0 = perfect). `tintPercent` is positive toward green.
    public func ingestCard(kelvin: Double?, tintPercent: Double, neutralError: Double?, linear lin: RGB, clipped: Bool) {
        usingCard = true
        if held != nil { return }
        let rgb = RGB(r: ColorMath.toSRGB(lin.r), g: ColorMath.toSRGB(lin.g), b: ColorMath.toSRGB(lin.b))
        let lum = ColorMath.luminance(r: rgb.r, g: rgb.g, b: rgb.b)
        guard let k = kelvin else {
            quality = lum < 0.08 ? .tooDark : .waiting
            return
        }
        let rawM = ColorMath.mired(k)
        let frameM = calibrated(rawMired: rawM)
        recentMired.append(frameM)
        if recentMired.count > 10 { recentMired.removeFirst() }

        if let done = progress {                      // "Measure": collect frames, then finish
            sum.r += lin.r; sum.g += lin.g; sum.b += lin.b
            sumRawMired += rawM
            sumTint += tintPercent
            sampledMired.append(frameM)
            let n = done + 1
            progress = n
            if n >= Self.framesPerMeasure {
                finishCard(frames: n)
                return
            }
        }

        if let prev = cardRawMired {
            cardRawMired = prev + (rawM - prev) * 0.25
            cardTint += (tintPercent - cardTint) * 0.25
        } else {
            cardRawMired = rawM
            cardTint = tintPercent
        }
        live = Reading(rgb: rgb, mired: calibrated(rawMired: cardRawMired!), luminance: lum, tint: cardTint, spreadK: nil)

        if clipped || lum > 0.95 { quality = .tooBright }
        else if lum < 0.08 { quality = .tooDark }
        else if let e = neutralError, e > 0.03 { quality = .settling }       // still adjusting white balance to the card
        else if recentMired.count >= 10 && Self.standardDeviation(recentMired) > 15 { quality = .moving }
        else if recentMired.count >= 10 && Self.standardDeviation(recentMired) > 6 { quality = .settling }
        else { quality = .steady }
    }

    private func calibrated(rawMired m: Double) -> Double {
        let fit = Calibration.fit(calPoints, legacyShift: legacyShift)
        return max(80, min(700, fit.a * m + fit.b))
    }

    private func finishCard(frames n: Int) {
        let count = Double(n)
        let lin = RGB(r: sum.r / count, g: sum.g / count, b: sum.b / count)
        let rgb = RGB(r: ColorMath.toSRGB(lin.r), g: ColorMath.toSRGB(lin.g), b: ColorMath.toSRGB(lin.b))
        let rawM = sumRawMired / count
        let m = calibrated(rawMired: rawM)
        var spread = 0
        if !sampledMired.isEmpty {
            spread = Int((abs(1e6 / m - 1e6 / (m + Self.standardDeviation(sampledMired))) / 10).rounded()) * 10
        }
        held = Reading(rgb: rgb, mired: m, luminance: ColorMath.luminance(r: rgb.r, g: rgb.g, b: rgb.b),
                       tint: sumTint / count, spreadK: spread)
        heldCardRawMired = rawM
        cardRawMired = rawM
        progress = nil
        quality = spread > 300 ? .noisy(spreadK: spread) : .measured(spreadK: spread)
    }

    /// Forget everything, e.g. after switching between Card and Manual mode (their numbers are not comparable).
    public func reset() {
        live = nil; held = nil; progress = nil; quality = .waiting
        smoothed = nil; heldLinear = nil
        usingCard = false; cardRawMired = nil; heldCardRawMired = nil; cardTint = 0
        recentMired = []; sampledMired = []
        sum = RGB(r: 0, g: 0, b: 0); sumRawMired = 0; sumTint = 0
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
        sumRawMired = 0
        sumTint = 0
        sampledMired = []
        progress = 0
    }

    /// Re-work the current reading with the latest calibration (after a point is added or removed).
    public func refresh() {
        if usingCard {
            if var h = held, let raw = heldCardRawMired {
                h.mired = calibrated(rawMired: raw)
                held = h
            } else if var l = live, let raw = cardRawMired {
                l.mired = calibrated(rawMired: raw)
                live = l
            }
            return
        }
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
        heldCardRawMired = nil
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
