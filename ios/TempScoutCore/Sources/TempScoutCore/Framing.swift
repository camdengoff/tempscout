import Foundation

/// Field of view and framing maths for "what would that camera and lens see".
public enum Framing {
    private static let rad = Double.pi / 180
    private static let deg = 180 / Double.pi
    /// Diagonal of a full-frame 36 x 24 sensor
    public static let fullFrameDiagonalMM = 43.2666

    /// Angle of view in degrees across `sizeMM` of sensor with a lens of focal length `focalMM` (rectilinear lens).
    public static func fieldOfView(sizeMM: Double, focalMM: Double) -> Double {
        2 * atan(sizeMM / (2 * focalMM)) * deg
    }

    /// The largest frame of a given shape (width / height) that fits inside the recording area. nil = the whole area.
    public static func frame(widthMM w: Double, heightMM h: Double, aspect: Double?) -> (width: Double, height: Double) {
        guard let a = aspect, a > 0 else { return (w, h) }
        if a >= w / h { return (w, w / a) }          // wider than the sensor: full width, cut top and bottom
        return (h * a, h)                             // narrower: full height, cut the sides
    }

    /// "Equivalent to this focal length on full frame" (by diagonal), the usual way to compare lenses across sensors.
    public static func fullFrameEquivalent(focalMM: Double, diagonalMM: Double) -> Double {
        focalMM * fullFrameDiagonalMM / diagonalMM
    }
}

/// How the phone's own camera maps the world onto the screen, so a different camera's frame can be drawn on top of
/// the live picture at its true size. The phone's picture fills the view (cropped, not squashed), and the world is
/// projected like any rectilinear lens: distance on screen = focal length in pixels x tan(angle).
public struct Viewfinder: Equatable {
    /// Angle of view along the long side of the phone camera's frame, at 1x zoom
    public var longFOVDegrees: Double
    public var longPixels: Double
    public var shortPixels: Double

    public init(longFOVDegrees: Double, longPixels: Double, shortPixels: Double) {
        self.longFOVDegrees = longFOVDegrees; self.longPixels = longPixels; self.shortPixels = shortPixels
    }

    private static let rad = Double.pi / 180
    private static let deg = 180 / Double.pi

    /// Focal length of the phone camera in frame pixels
    public func focalPixels(zoom: Double = 1) -> Double {
        longPixels / 2 / tan(longFOVDegrees * Self.rad / 2) * zoom
    }

    /// Screen points per frame pixel, with the frame filling the view ("aspect fill")
    public func pointsPerPixel(viewWidth: Double, viewHeight: Double) -> Double {
        max(viewWidth / shortPixels, viewHeight / longPixels)
    }

    /// Size on screen, in points, of a span of `fovDegrees` of the world.
    public func points(forFOVDegrees fovDegrees: Double, viewWidth: Double, viewHeight: Double, zoom: Double = 1) -> Double {
        2 * tan(fovDegrees * Self.rad / 2) * focalPixels(zoom: zoom) * pointsPerPixel(viewWidth: viewWidth, viewHeight: viewHeight)
    }

    /// How much of the world the view shows across its width (the view is held upright, so width = the short side).
    public func visibleHorizontalFOV(viewWidth: Double, viewHeight: Double, zoom: Double = 1) -> Double {
        2 * atan((viewWidth / 2) / (pointsPerPixel(viewWidth: viewWidth, viewHeight: viewHeight) * focalPixels(zoom: zoom))) * Self.deg
    }

    /// The zoom that makes a frame of `horizontalFOVDegrees` take up `fraction` of the view width. Not limited to what the
    /// phone can really do: the caller clamps it.
    public func zoomToFill(horizontalFOVDegrees: Double, viewWidth: Double, viewHeight: Double, fraction: Double) -> Double {
        let atOneX = points(forFOVDegrees: horizontalFOVDegrees, viewWidth: viewWidth, viewHeight: viewHeight, zoom: 1)
        return atOneX > 0 ? fraction * viewWidth / atOneX : 1
    }
}
