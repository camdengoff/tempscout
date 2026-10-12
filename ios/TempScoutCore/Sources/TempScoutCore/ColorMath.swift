import Foundation

/// A colour as three numbers. Used both for 0-255 sRGB values and for 0-1 linear light;
/// each place says which.
public struct RGB: Equatable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }
}

/// Turns the average Red/Green/Blue of the picture into an estimated colour temperature in Kelvin.
public enum ColorMath {
    /// sRGB white (R = G = B) reads as this temperature.
    public static let d65Kelvin = 6504.0

    /// Camera values are "gamma encoded"; this converts 0-255 to real light amounts (0-1).
    public static func toLinear(_ c: Double) -> Double {
        let v = c / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// Back from linear light (0-1) to a 0-255 sRGB value.
    public static func toSRGB(_ lin: Double) -> Double {
        let c = max(lin, 0)
        return 255 * (c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055)
    }

    /// "Mired" is a scale where equal steps look equally different, handy for shifting and comparing.
    public static func mired(_ kelvin: Double) -> Double { 1e6 / kelvin }

    /// sRGB (0-255) -> Kelvin using the standard McCamy formula. Nil if too dark to measure.
    public static func rgbToKelvin(r: Double, g: Double, b: Double) -> Double? {
        let rl = toLinear(r), gl = toLinear(g), bl = toLinear(b)
        let x = 0.4124 * rl + 0.3576 * gl + 0.1805 * bl
        let y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
        let z = 0.0193 * rl + 0.1192 * gl + 0.9505 * bl
        let sum = x + y + z
        if sum < 0.002 { return nil }
        let cx = x / sum, cy = y / sum
        let n = (cx - 0.3320) / (0.1858 - cy)
        let k = 449 * n * n * n + 3525 * n * n + 6823.3 * n + 5520.33
        return max(1500, min(12000, k))
    }

    /// Green/magenta shift in percent: positive = toward green.
    public static func tint(r: Double, g: Double, b: Double) -> Double {
        ((g - (r + b) / 2) / max(1, (r + g + b) / 3)) * 100
    }

    /// 0...1 brightness of an sRGB colour.
    public static func luminance(r: Double, g: Double, b: Double) -> Double {
        (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    }

    /// The light in plain words.
    public static func lightName(_ k: Double) -> String {
        if k < 2800 { return "Candle / tungsten glow" }
        if k < 3500 { return "Warm tungsten" }
        if k < 4500 { return "Warm white" }
        if k < 5200 { return "Neutral white" }
        if k < 6000 { return "Daylight" }
        if k < 7500 { return "Overcast / cool" }
        return "Shade / blue sky"
    }
}
