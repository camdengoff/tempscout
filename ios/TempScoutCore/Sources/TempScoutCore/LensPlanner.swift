import Foundation

/// One of the phone's cameras, described by how it maps the world onto the screen.
public struct LensCandidate: Equatable {
    public var id: String
    public var viewfinder: Viewfinder

    public init(id: String, viewfinder: Viewfinder) {
        self.id = id; self.viewfinder = viewfinder
    }
}

/// Chooses which of the phone's cameras to use for a frame, the way a camera app picks 0.5x / 1x / 3x.
public enum LensPlanner {
    /// A camera can show the frame if it only needs to zoom IN to fill the screen with it (zoom of 1 or more).
    /// Of those, the one that needs the least zoom is best: it is the narrowest view that still covers the frame, so the
    /// least digital cropping. If the frame is wider than every camera can show, use the widest camera.
    /// Returns nil if there are no cameras.
    public static func bestCamera(horizontalFOV frame: Double, candidates: [LensCandidate],
                                  viewWidth: Double, viewHeight: Double, fraction: Double = 0.92) -> String? {
        guard !candidates.isEmpty else { return nil }
        let zooms = candidates.map { c in
            (id: c.id, zoom: c.viewfinder.zoomToFill(horizontalFOVDegrees: frame, viewWidth: viewWidth, viewHeight: viewHeight, fraction: fraction))
        }
        if let best = zooms.filter({ $0.zoom >= 1 }).min(by: { $0.zoom < $1.zoom }) {
            return best.id
        }
        let widest = candidates.max {
            $0.viewfinder.visibleHorizontalFOV(viewWidth: viewWidth, viewHeight: viewHeight)
                < $1.viewfinder.visibleHorizontalFOV(viewWidth: viewWidth, viewHeight: viewHeight)
        }
        return widest?.id
    }
}
