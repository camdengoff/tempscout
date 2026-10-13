import Foundation

/// Exposure maths for ND planning. "EV" here is always exposure value at ISO 100: log2(f-number squared / shutter seconds),
/// minus log2(ISO / 100). A brighter scene has a higher EV.
public enum ExposureMath {
    /// How bright the scene is, from what the phone's own auto exposure chose (which aims to render the metered area as mid-grey).
    public static func sceneEV(aperture: Double, shutterSeconds: Double, iso: Double) -> Double {
        log2(aperture * aperture / shutterSeconds) - log2(iso / 100)
    }

    /// Shutter time for a shutter angle at a frame rate: 180 degrees at 24 fps is 1/48 s.
    public static func shutterSeconds(angle: Double, fps: Double) -> Double {
        angle / 360 / fps
    }

    /// The scene EV that these camera settings (plus an ND filter of `ndStops`) expose correctly.
    public static func evForSettings(fStop: Double, shutterSeconds: Double, iso: Double, ndStops: Double) -> Double {
        log2(fStop * fStop / shutterSeconds) - log2(iso / 100) + ndStops
    }

    /// Stops over (+) or under (-) exposed with these settings and ND filter.
    public static func exposureError(sceneEV: Double, fStop: Double, shutterSeconds: Double, iso: Double, ndStops: Double) -> Double {
        sceneEV - evForSettings(fStop: fStop, shutterSeconds: shutterSeconds, iso: iso, ndStops: ndStops)
    }

    /// Stops of ND needed for correct exposure (0 if none is needed).
    public static func ndNeeded(sceneEV: Double, fStop: Double, shutterSeconds: Double, iso: Double) -> Double {
        max(0, exposureError(sceneEV: sceneEV, fStop: fStop, shutterSeconds: shutterSeconds, iso: iso, ndStops: 0))
    }

    /// "Correct", "+1.3 stops over" or "-2.0 stops under".
    public static func describe(error: Double) -> String {
        if abs(error) < 0.34 { return "Correct" }
        return String(format: "%+.1f stops ", error) + (error > 0 ? "over" : "under")
    }
}
