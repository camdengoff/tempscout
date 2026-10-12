import Foundation

public struct SunPosition: Equatable {
    /// Compass direction, degrees clockwise from true north
    public var azimuth: Double
    /// Degrees above the horizon (negative = below)
    public var altitude: Double
}

/// Standard sunrise/sunset and solar position maths. Accurate to a few minutes / well under a degree.
public enum SunMath {
    private static let rad = Double.pi / 180
    private static let deg = 180 / Double.pi

    static func mod(_ n: Double, _ m: Double) -> Double {
        let r = n.truncatingRemainder(dividingBy: m)
        return (r + m).truncatingRemainder(dividingBy: m)
    }

    /// Where the sun is in the sky (NOAA-style).
    public static func position(date: Date, latitude: Double, longitude: Double) -> SunPosition {
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0      // days since J2000
        let l = mod(280.460 + 0.9856474 * n, 360)
        let g = mod(357.528 + 0.9856003 * n, 360) * rad
        let lambda = (l + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let eps = (23.439 - 0.0000004 * n) * rad
        let ra = atan2(cos(eps) * sin(lambda), cos(lambda))
        let dec = asin(sin(eps) * sin(lambda))
        let hourAngle = mod(280.46061837 + 360.98564736629 * n + longitude, 360) * rad - ra
        let la = latitude * rad
        let alt = asin(sin(la) * sin(dec) + cos(la) * cos(dec) * cos(hourAngle))
        let az = atan2(sin(hourAngle), cos(hourAngle) * sin(la) - tan(dec) * cos(la)) * deg + 180
        return SunPosition(azimuth: mod(az, 360), altitude: alt * deg)
    }

    /// Time of sunrise/sunset (or twilight / golden hour, by choosing `zenith`) on the calendar day of `date`.
    /// zenith: 90.833 = sunrise/sunset, 84 = golden hour, 96 = first/last light.
    /// Returns nil when the sun never rises/sets that day.
    public static func event(date: Date, latitude: Double, longitude: Double,
                             rising: Bool, zenith: Double, calendar: Calendar = .current) -> Date? {
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let lngHour = longitude / 15
        let n = Double(dayOfYear)
        let t = n + ((rising ? 6.0 : 18.0) - lngHour) / 24
        let m = 0.9856 * t - 3.289
        let l = mod(m + 1.916 * sin(m * rad) + 0.020 * sin(2 * m * rad) + 282.634, 360)
        var ra = mod(deg * atan(0.91764 * tan(l * rad)), 360)
        ra += floor(l / 90) * 90 - floor(ra / 90) * 90
        ra /= 15
        let sinDec = 0.39782 * sin(l * rad)
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(zenith * rad) - sinDec * sin(latitude * rad)) / (cosDec * cos(latitude * rad))
        if cosH > 1 || cosH < -1 { return nil }
        var h = rising ? 360 - deg * acos(cosH) : deg * acos(cosH)
        h /= 15
        let tt = h + ra - 0.06571 * t - 6.622
        let ut = mod(tt - lngHour, 24)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let base = utc.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day)) else { return nil }
        var result = base.addingTimeInterval(ut * 3600)
        // West of Greenwich the UT time can land on the next/previous UTC day; keep it on the local day asked for.
        for shift in [-86400.0, 86400.0] where !calendar.isDate(result, inSameDayAs: date) {
            let moved = result.addingTimeInterval(shift)
            if calendar.isDate(moved, inSameDayAs: date) { result = moved; break }
        }
        return result
    }
}
