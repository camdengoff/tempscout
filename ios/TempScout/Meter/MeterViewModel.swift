import Combine
import Foundation
import TempScoutCore

/// How a reading is made.
enum MeasureMode: String {
    /// Point at the light or scene: the camera's own automatic white balance estimate (default, no setup).
    case scene
    /// Hold a gray or white card in the square: the app adjusts white balance to the card, then reads the temperature.
    case card
    /// Advanced: lock white balance yourself and calibrate against known lights.
    case manual
}

/// Connects the camera to the colour engine and holds the settings.
final class MeterViewModel: ObservableObject {
    let camera: CameraController
    private let engine = MeterEngine()
    private var bag = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    // What the screen shows
    @Published private(set) var reading: Reading?
    @Published private(set) var quality: MeterQuality = .waiting
    @Published private(set) var progress: Int?
    @Published private(set) var isHeld = false
    @Published private(set) var autoKelvin: Double?
    @Published private(set) var lockedKelvin: Double?

    // Settings (saved)
    @Published private(set) var mode: MeasureMode
    /// Scene and Card both use the camera's own colour temperature; only Manual works it out from the picture.
    var usesCameraKelvin: Bool { mode != .manual }
    @Published private(set) var wantLock: Bool
    @Published private(set) var wbKelvin: Double
    @Published private(set) var exposureLockWanted: Bool
    @Published var areaFraction: Double { didSet { defaults.set(areaFraction, forKey: "ts_area") } }
    @Published var referenceKelvin: Int? { didSet { defaults.set(referenceKelvin, forKey: "ts_ref_k") } }
    @Published var calPoints: [CalPoint] {
        didSet {
            engine.calPoints = calPoints
            engine.refresh()
            sync()
            if let data = try? JSONEncoder().encode(calPoints) { defaults.set(data, forKey: Self.calibrationKey(mode)) }
        }
    }

    init(camera: CameraController) {
        self.camera = camera
        let d = UserDefaults.standard
        let startMode = MeasureMode(rawValue: d.string(forKey: "ts_mode") ?? "") ?? .scene
        mode = startMode
        wantLock = d.object(forKey: "ts_wb_lock") as? Bool ?? true
        wbKelvin = d.object(forKey: "ts_wb_k") as? Double ?? 5500
        exposureLockWanted = d.object(forKey: "ts_exp_lock") as? Bool ?? false
        areaFraction = d.object(forKey: "ts_area") as? Double ?? 0.2
        referenceKelvin = d.object(forKey: "ts_ref_k") as? Int
        if let data = d.data(forKey: Self.calibrationKey(startMode)), let pts = try? JSONDecoder().decode([CalPoint].self, from: data) {
            calPoints = pts
        } else {
            calPoints = []
        }
        engine.calPoints = calPoints

        camera.onSample = { [weak self] sample in self?.handle(sample) }
        camera.$lockedKelvin
            .sink { [weak self] k in self?.lockChanged(to: k) }
            .store(in: &bag)
        camera.$status
            .sink { [weak self] status in if status == .running { self?.applyCameraSettings() } }
            .store(in: &bag)
        // a different camera starts with its own white balance and exposure, so apply the chosen mode to it
        camera.$activeCamera
            .dropFirst()
            .sink { [weak self] _ in self?.applyCameraSettings() }
            .store(in: &bag)
        // let views that watch this model also redraw when the camera's own state changes
        camera.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    // MARK: - Camera events

    private func handle(_ sample: CameraSample) {
        autoKelvin = sample.autoKelvin
        if usesCameraKelvin {
            engine.ingestCard(kelvin: sample.cardKelvin, tintPercent: sample.cardTintPercent,
                              neutralError: sample.neutralError, linear: sample.linear, clipped: sample.clipped)
        } else {
            engine.ingest(linear: sample.linear, clipped: sample.clipped)
        }
        sync()
    }

    private func sync() {
        reading = engine.current
        quality = engine.quality
        progress = engine.progress
        isHeld = engine.isHeld
    }

    private func lockChanged(to k: Double?) {
        if usesCameraKelvin { lockedKelvin = k; return }          // Scene and Card manage the white balance themselves
        // a different white balance means a held reading no longer applies
        engine.lockedKelvin = k
        if engine.isHeld {
            engine.resume()
            camera.freezeExposure(false)
        }
        lockedKelvin = k
        sync()
    }

    private func applyCameraSettings() {
        switch mode {
        case .scene:
            camera.setReadMode(.scene)
            camera.setWhiteBalance(kelvin: nil)                 // the camera's own automatic white balance
        case .card:
            camera.setReadMode(.card)
        case .manual:
            camera.setReadMode(.off)
            camera.setWhiteBalance(kelvin: wantLock ? wbKelvin : nil)
        }
        camera.setExposureLocked(exposureLockWanted)
    }

    private static func calibrationKey(_ mode: MeasureMode) -> String {
        switch mode {
        case .scene: return "ts_cal_scene"
        case .card: return "ts_cal_card"
        case .manual: return "ts_cal_pts"
        }
    }

    /// Switch mode. Their numbers are not comparable, so each keeps its own calibration points.
    func setMode(_ new: MeasureMode) {
        guard new != mode else { return }
        mode = new
        defaults.set(new.rawValue, forKey: "ts_mode")
        var pts: [CalPoint] = []
        if let data = defaults.data(forKey: Self.calibrationKey(new)),
           let saved = try? JSONDecoder().decode([CalPoint].self, from: data) { pts = saved }
        calPoints = pts                               // (saved again under the new mode's key, which is harmless)
        engine.reset()
        engine.calPoints = pts
        camera.freezeExposure(false)
        applyCameraSettings()
        sync()
    }

    // MARK: - Actions

    func toggleMeasure() {
        if engine.isHeld {
            engine.resume()
            camera.freezeExposure(false)            // exposure follows the square again
        } else if engine.progress == nil {
            engine.startMeasuring()
            camera.freezeExposure(true)             // hold brightness steady for the 3 seconds
        }
        sync()
    }

    func setWhiteBalanceLock(_ on: Bool) {
        wantLock = on
        defaults.set(on, forKey: "ts_wb_lock")
        camera.setWhiteBalance(kelvin: on ? wbKelvin : nil)
    }

    func setWhiteBalanceKelvin(_ k: Double) {
        wbKelvin = k
        defaults.set(k, forKey: "ts_wb_k")
        if wantLock { camera.setWhiteBalance(kelvin: k) }
    }

    func setExposureLock(_ on: Bool) {
        exposureLockWanted = on
        defaults.set(on, forKey: "ts_exp_lock")
        camera.setExposureLocked(on)
    }

    /// Use the reading on screen as a known light of `knownKelvin`. Returns false if there is nothing to calibrate from.
    func addCalibrationPoint(knownKelvin: Double) -> Bool {
        guard knownKelvin > 1000, let m = engine.measuredMiredForCalibration() else { return false }
        calPoints = Calibration.adding(CalPoint(m: m, t: ColorMath.mired(knownKelvin)), to: calPoints)
        return true
    }

    func resetCalibration() { calPoints = [] }

    /// What the camera says right now, before calibration (for the diagnostic in Settings).
    var uncalibratedKelvin: Double? { engine.uncalibratedKelvin() }

    func setReferenceFromReading() {
        referenceKelvin = reading?.displayKelvin
    }

    func makeShot(note: String) -> Shot? {
        guard let r = reading, let k = r.displayKelvin else { return nil }
        return Shot(kelvin: k, tint: (r.tint * 10).rounded() / 10, brightness: Int((r.luminance * 100).rounded()),
                    rgb: [r.rgb.r, r.rgb.g, r.rgb.b].map { Int($0.rounded()) }, note: note)
    }

    static func qualityText(_ q: MeterQuality, mode: MeasureMode) -> String {
        switch q {
        case .waiting: return mode == .card ? "Point at a white or gray card" : "Point at the light or scene"
        case .tooBright: return "Too bright — tilt away or step back"
        case .tooDark: return "Too dark — move into more light"
        case .moving: return "Moving — hold steady"
        case .settling: return "Settling…"
        case .steady: return mode == .card ? "Steady ✓ Tap the shutter to average" : "Steady ✓ Tap the shutter to average 3 seconds"
        case .measured: return "Measured: 30-frame average ✓"
        case .noisy(let k): return "Frames disagreed (±\(k)K) — hold steadier, retry"
        }
    }
}
