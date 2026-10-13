import SwiftUI

// The ND page needs the camera and the live exposure model, but it must NOT re-draw every time they publish a new reading
// (about ten times a second): a pop-up menu that is rebuilt while it is open cannot scroll or take a tap.
// Passing them through the environment (instead of as observed objects) hands over the objects without subscribing to them;
// only the small views that show live numbers observe them.
private struct FrameCameraKey: EnvironmentKey {
    static let defaultValue: CameraController? = nil
}

private struct FrameLiveKey: EnvironmentKey {
    static let defaultValue: FrameLiveModel? = nil
}

extension EnvironmentValues {
    var frameCamera: CameraController? {
        get { self[FrameCameraKey.self] }
        set { self[FrameCameraKey.self] = newValue }
    }

    var frameLive: FrameLiveModel? {
        get { self[FrameLiveKey.self] }
        set { self[FrameLiveKey.self] = newValue }
    }
}
