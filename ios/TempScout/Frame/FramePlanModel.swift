import Foundation
import TempScoutCore

/// The camera, lens, frame shape and exposure settings you are planning with. Shared by the ND page and the Meter's ND row.
final class FramePlanModel: ObservableObject {
    struct Settings: Codable {
        var cameraID = Gear.defaultCameraID
        var focal = 35.0
        var aspectID = "2.39"
        var vertical = false
        var fps = 24.0
        var angle = 180.0
        var iso = 800.0
        var fStop = 2.8
        /// nil = Auto: use whatever ND the scene needs
        var ndStops: Double?
        var zoomToFrame = true
        var dimOutside = true
        var previewExposure = true
        var customCameras: [CameraFormat] = []
        /// Which of the phone's cameras to use. nil = automatic: the app picks the one that suits the lens and frame.
        var phoneCamera: String?
    }

    @Published var settings: Settings { didSet { save() } }
    private static let key = "ts_frame_plan_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = saved
        } else {
            settings = Settings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    // MARK: - Gear

    var allCameras: [CameraFormat] { Gear.cameras + settings.customCameras }

    var camera: CameraFormat {
        allCameras.first { $0.id == settings.cameraID } ?? Gear.cameras[0]
    }

    var aspect: AspectOption {
        Gear.aspects.first { $0.id == settings.aspectID } ?? Gear.aspects[0]
    }

    /// The built-in focal lengths, plus the current one if it is a custom value.
    var focalOptions: [Double] {
        Gear.focalLengths.contains(settings.focal) ? Gear.focalLengths : (Gear.focalLengths + [settings.focal]).sorted()
    }

    func addCustomCamera(name: String, widthMM: Double, heightMM: Double) {
        let cam = CameraFormat(id: "custom-" + UUID().uuidString, name: name.isEmpty ? "Custom camera" : name,
                               widthMM: widthMM, heightMM: heightMM, isCustom: true)
        settings.customCameras.append(cam)
        settings.cameraID = cam.id
    }

    func deleteCustomCameras(at offsets: IndexSet) {
        let removed = offsets.map { settings.customCameras[$0].id }
        settings.customCameras.remove(atOffsets: offsets)
        if removed.contains(settings.cameraID) { settings.cameraID = Gear.defaultCameraID }
    }

    // MARK: - Framing

    /// The frame, in millimetres on the sensor, after the aspect ratio (and vertical shooting) is applied
    var frameMM: (width: Double, height: Double) {
        let f = Framing.frame(widthMM: camera.widthMM, heightMM: camera.heightMM, aspect: aspect.ratio)
        return settings.vertical ? (f.height, f.width) : f
    }

    var horizontalFOV: Double { Framing.fieldOfView(sizeMM: frameMM.width, focalMM: settings.focal) }
    var verticalFOV: Double { Framing.fieldOfView(sizeMM: frameMM.height, focalMM: settings.focal) }
    var fullFrameEquivalent: Double { Framing.fullFrameEquivalent(focalMM: settings.focal, diagonalMM: camera.diagonalMM) }

    // MARK: - Exposure

    var shutterSeconds: Double { ExposureMath.shutterSeconds(angle: settings.angle, fps: settings.fps) }
    var shutterLabel: String { "1/\(Int((1 / shutterSeconds).rounded()))" }

    var ndLabel: String {
        guard let stops = settings.ndStops else { return "ND auto" }
        return NDFilter(stops: stops).label
    }
}
