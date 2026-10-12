import Foundation

public struct Exposure: Equatable, Codable {
    public var aperture: Double   // f-number
    public var shutter: Double    // seconds
    public var iso: Double
    public init(aperture: Double, shutter: Double, iso: Double) {
        self.aperture = aperture; self.shutter = shutter; self.iso = iso
    }
}

/// "Stops" = how many times the light doubles or halves.
/// Light amount is proportional to shutter time x ISO / aperture squared.
public enum NDCalculator {
    public static let apertures: [Double] = [1.4, 1.8, 2, 2.8, 4, 5.6, 8, 11, 16, 22]
    public static let isos: [Double] = [50, 100, 200, 400, 800, 1600, 3200, 6400]
    public struct ShutterOption: Identifiable, Equatable {
        public let label: String
        public let seconds: Double
        public var id: Double { seconds }
    }

    public static let shutters: [ShutterOption] = [
        ShutterOption(label: "1/4000", seconds: 1.0 / 4000), ShutterOption(label: "1/2000", seconds: 1.0 / 2000),
        ShutterOption(label: "1/1000", seconds: 1.0 / 1000), ShutterOption(label: "1/500", seconds: 1.0 / 500),
        ShutterOption(label: "1/250", seconds: 1.0 / 250), ShutterOption(label: "1/125", seconds: 1.0 / 125),
        ShutterOption(label: "1/100", seconds: 1.0 / 100), ShutterOption(label: "1/60", seconds: 1.0 / 60),
        ShutterOption(label: "1/50", seconds: 1.0 / 50), ShutterOption(label: "1/48", seconds: 1.0 / 48),
        ShutterOption(label: "1/30", seconds: 1.0 / 30), ShutterOption(label: "1/24", seconds: 1.0 / 24),
        ShutterOption(label: "1/15", seconds: 1.0 / 15), ShutterOption(label: "1/8", seconds: 1.0 / 8),
        ShutterOption(label: "1/4", seconds: 1.0 / 4), ShutterOption(label: "1/2", seconds: 1.0 / 2),
        ShutterOption(label: "1 sec", seconds: 1)
    ]

    public static func shutterLabel(_ seconds: Double) -> String {
        if let o = shutters.first(where: { abs($0.seconds - seconds) < 1e-9 }) { return o.label }
        return seconds >= 1 ? String(format: "%.1f sec", seconds) : "1/\(Int((1 / seconds).rounded()))"
    }

    public static func lightAmount(_ e: Exposure) -> Double {
        e.shutter * e.iso / (e.aperture * e.aperture)
    }

    public struct Result: Equatable {
        /// exact stops difference (positive = the wanted settings let in MORE light, so ND is needed)
        public let stops: Double
        /// nearest 1/3 stop
        public let thirdStops: Double
        /// stops of ND to add (0 if none is needed)
        public let needed: Double
    }

    public static func compute(base: Exposure, wanted: Exposure) -> Result {
        let stops = log2(lightAmount(wanted) / lightAmount(base))
        let rounded = (stops * 3).rounded() / 3
        return Result(stops: stops, thirdStops: rounded, needed: rounded > 0.15 ? rounded : 0)
    }

    public static func apertureLabel(_ a: Double) -> String {
        "f/" + (a.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(a)) : String(a))
    }

    public static func isoLabel(_ i: Double) -> String { String(Int(i)) }

    /// Like "ND 4 (1.2)": stops, then density (0.3 per stop).
    public static func summary(_ result: Result) -> String {
        "ND " + trimmed(result.needed) + " (" + String(format: "%.1f", result.needed * 0.3) + ")"
    }

    static func trimmed(_ v: Double) -> String {
        var s = String(format: "%.1f", v)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s
    }
}
