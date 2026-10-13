import AVFoundation
import Combine
import TempScoutCore
import UIKit

/// One reading of the measure square, about ten times a second.
struct CameraSample {
    /// Average colour in the square, in linear light (0-1)
    var linear: RGB
    /// More than 10% of the pixels are blown out
    var clipped: Bool
    /// While white balance is on automatic: the temperature the camera itself thinks the light is
    var autoKelvin: Double?
    /// Card mode: the colour temperature Apple's calibration gives for the white balance gains that make the card neutral
    var cardKelvin: Double?
    /// Card mode: green/magenta shift of the light in percent, positive = toward green
    var cardTintPercent: Double = 0
    /// Card mode: how far from neutral the card still looks (0 = neutral); nil when it can't be judged
    var neutralError: Double?
    /// How bright the scene is (EV at ISO 100) from the camera's own auto exposure, with any exposure bias taken out
    var sceneEV: Double?
}

/// The phone's back cameras. The Meter always uses the Wide camera; the ND page switches between them to suit the lens you choose.
enum LensCamera: String, CaseIterable {
    case ultraWide, wide, telephoto

    var title: String {
        switch self {
        case .ultraWide: return "Ultra Wide"
        case .wide: return "Wide"
        case .telephoto: return "Telephoto"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
}

/// Owns the camera. This is the reason the app exists: unlike a web page, it can LOCK the white balance
/// (and exposure), so the same card under the same light gives the same pixels every time.
final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Status: Equatable {
        case idle, running, denied
        case failed(String)
    }

    let session = AVCaptureSession()
    @Published private(set) var status: Status = .idle
    @Published private(set) var whiteBalanceLockSupported = false
    /// nil = automatic white balance; otherwise the Kelvin the camera is locked at
    @Published private(set) var lockedKelvin: Double?
    @Published private(set) var exposureLocked = false
    /// How this phone's camera maps the world onto the screen (for drawing other cameras' frames over the picture)
    @Published private(set) var viewfinder: Viewfinder?
    /// Which back cameras this phone has, which one is in use, and how each maps the world onto the screen
    @Published private(set) var availableCameras: [LensCamera] = [.wide]
    @Published private(set) var activeCamera: LensCamera = .wide
    @Published private(set) var cameraViewfinders: [LensCamera: Viewfinder] = [:]
    @Published private(set) var zoom: Double = 1
    @Published private(set) var maxZoom: Double = 1

    /// Every reading, for screens that need more than one listener. (`onSample` is used by the Meter.)
    let samples = PassthroughSubject<CameraSample, Never>()

    /// Called on the main thread, about 10 times a second.
    var onSample: ((CameraSample) -> Void)?

    private let sessionQueue = DispatchQueue(label: "tempscout.camera.session")
    private let sampleQueue = DispatchQueue(label: "tempscout.camera.samples")
    private var device: AVCaptureDevice?
    private var devices: [LensCamera: AVCaptureDevice] = [:]     // session queue
    private var activeKind = LensCamera.wide                      // session queue
    private var biasValue = 0.0                                   // session queue: last exposure bias asked for
    private var configured = false

    // Exposure follows the white square. It can be held still two ways: by the user (Settings) or while a Measure runs.
    private var userLocksExposure = false
    private var exposureFrozenForMeasure = false
    private var lastMeteredPoint = CGPoint(x: -1, y: -1)

    // Card mode: the app adjusts the camera's white balance until the card in the square looks neutral.
    private let flagLock = NSLock()
    private var readModeFlag = ReadMode.off
    private var lastServoTime = CFAbsoluteTimeGetCurrent()

    // The measure square, in the camera's own 0-1 coordinates. Written from the main thread, read from the sample queue.
    private let roiLock = NSLock()
    private var roi = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
    private var lastSampleTime = CFAbsoluteTimeGetCurrent()

    // 0-255 -> linear light, looked up instead of calculated for every pixel
    private static let linearTable: [Double] = (0..<256).map { ColorMath.toLinear(Double($0)) }

    // MARK: - Start / stop

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureAndRun() } else { self?.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.status = .idle }
        }
    }

    // The Meter and the ND page share one camera. Each asks for it when it appears and gives it back when it leaves;
    // the camera only stops when nobody wants it. (Call from the main thread.)
    private var users = 0

    func acquire() {
        users += 1
        start()
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { stop() }
    }

    /// Make the picture brighter or darker by `stops` (the camera still meters automatically around that).
    func setExposureBias(_ stops: Double) {
        sessionQueue.async { [weak self] in
            guard let self = self, let dev = self.device else { return }
            self.biasValue = stops
            let bias = max(Double(dev.minExposureTargetBias), min(Double(dev.maxExposureTargetBias), stops))
            do {
                try dev.lockForConfiguration()
                defer { dev.unlockForConfiguration() }
                dev.setExposureTargetBias(Float(bias), completionHandler: nil)
            } catch {
                // keep the current bias
            }
        }
    }

    /// Digital zoom (1 = none), limited to what the camera supports.
    func setZoom(_ factor: Double) {
        sessionQueue.async { [weak self] in
            guard let self = self, let dev = self.device else { return }
            let limit = min(Double(dev.activeFormat.videoMaxZoomFactor), 8)
            let z = max(1, min(limit, factor))
            do {
                try dev.lockForConfiguration()
                defer { dev.unlockForConfiguration() }
                dev.videoZoomFactor = CGFloat(z)
                DispatchQueue.main.async { self.zoom = z }
            } catch {
                // keep the current zoom
            }
        }
    }

    /// Measure the brightness at the middle of the picture (used by the ND page, which looks at the whole scene).
    func meterAtCenter() {
        sessionQueue.async { [weak self] in
            self?.lastMeteredPoint = CGPoint(x: -1, y: -1)
        }
        meterExposure(atNormalizedPoint: CGPoint(x: 0.5, y: 0.5))
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.exposureFrozenForMeasure = false
            if !self.configured {
                guard self.configureSession() else { return }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { self.status = .failed(message) }
    }

    /// Runs on the session queue.
    private func configureSession() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else {
            session.commitConfiguration()
            fail("Couldn't open the back camera.")
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            fail("Couldn't read frames from the camera.")
            return false
        }
        session.addOutput(output)
        session.commitConfiguration()

        device = dev
        configured = true
        prepareForMeasuring(dev)
        meterExposure(atNormalizedPoint: nil)
        let supported = dev.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        let dims = CMVideoFormatDescriptionGetDimensions(dev.activeFormat.formatDescription)
        let finder = Viewfinder(longFOVDegrees: Double(dev.activeFormat.videoFieldOfView),
                                longPixels: Double(max(dims.width, dims.height)),
                                shortPixels: Double(min(dims.width, dims.height)))
        let zoomLimit = min(Double(dev.activeFormat.videoMaxZoomFactor), 8)

        // find the other back cameras, so the ND page can switch between them
        var found: [LensCamera: AVCaptureDevice] = [:]
        for kind in LensCamera.allCases {
            if let d = AVCaptureDevice.default(kind.deviceType, for: .video, position: .back) { found[kind] = d }
        }
        found[.wide] = dev
        devices = found
        activeKind = .wide
        var finders: [LensCamera: Viewfinder] = [:]
        for (kind, d) in found { finders[kind] = kind == .wide ? finder : estimatedViewfinder(for: d) }
        let kinds = LensCamera.allCases.filter { found[$0] != nil }

        DispatchQueue.main.async {
            self.whiteBalanceLockSupported = supported
            self.viewfinder = finder
            self.maxZoom = zoomLimit
            self.availableCameras = kinds
            self.activeCamera = .wide
            self.cameraViewfinders = finders
        }
        return true
    }

    /// What a camera's picture will look like once the session is using it, worked out from its 16:9 video format
    /// (before it is switched to, we can't ask it directly).
    private func estimatedViewfinder(for dev: AVCaptureDevice) -> Viewfinder {
        let candidates = dev.formats.filter { f in
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            return d.width >= 1280 && abs(Double(d.width) / Double(d.height) - 16.0 / 9.0) < 0.02
        }
        let format = candidates.min { a, b in
            CMVideoFormatDescriptionGetDimensions(a.formatDescription).width < CMVideoFormatDescriptionGetDimensions(b.formatDescription).width
        } ?? dev.activeFormat
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Viewfinder(longFOVDegrees: Double(format.videoFieldOfView),
                          longPixels: Double(max(d.width, d.height)), shortPixels: Double(min(d.width, d.height)))
    }

    /// Switch to another back camera (e.g. the ultra wide for a very wide lens, or the telephoto for a long one).
    func selectCamera(_ kind: LensCamera) {
        sessionQueue.async { [weak self] in
            guard let self = self, self.configured, kind != self.activeKind, let newDev = self.devices[kind],
                  let input = try? AVCaptureDeviceInput(device: newDev) else { return }

            self.session.beginConfiguration()
            let previous = self.session.inputs
            for old in previous { self.session.removeInput(old) }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            } else {
                for old in previous where self.session.canAddInput(old) { self.session.addInput(old) }   // put things back
                self.session.commitConfiguration()
                return
            }
            self.session.commitConfiguration()

            self.device = newDev
            self.activeKind = kind
            self.prepareForMeasuring(newDev)
            do {
                try newDev.lockForConfiguration()
                defer { newDev.unlockForConfiguration() }
                newDev.videoZoomFactor = 1
                let bias = max(Double(newDev.minExposureTargetBias), min(Double(newDev.maxExposureTargetBias), self.biasValue))
                newDev.setExposureTargetBias(Float(bias), completionHandler: nil)
            } catch {
                // keep the new camera's defaults
            }
            self.lastMeteredPoint = CGPoint(x: -1, y: -1)
            self.meterExposure(atNormalizedPoint: nil)

            let dims = CMVideoFormatDescriptionGetDimensions(newDev.activeFormat.formatDescription)
            let finder = Viewfinder(longFOVDegrees: Double(newDev.activeFormat.videoFieldOfView),
                                    longPixels: Double(max(dims.width, dims.height)),
                                    shortPixels: Double(min(dims.width, dims.height)))
            let zoomLimit = min(Double(newDev.activeFormat.videoMaxZoomFactor), 8)
            DispatchQueue.main.async {
                self.viewfinder = finder
                self.cameraViewfinders[kind] = finder
                self.maxZoom = zoomLimit
                self.zoom = 1
                self.activeCamera = kind
            }
        }
    }

    /// Turn off the things that would quietly change colours: wide-gamut colour and HDR processing.
    private func prepareForMeasuring(_ dev: AVCaptureDevice) {
        do {
            try dev.lockForConfiguration()
            defer { dev.unlockForConfiguration() }
            // plain sRGB, so the colour maths matches what we sample
            if dev.activeFormat.supportedColorSpaces.contains(.sRGB) {
                dev.activeColorSpace = .sRGB
            }
            if dev.activeFormat.isVideoHDRSupported {
                dev.automaticallyAdjustsVideoHDREnabled = false
                dev.isVideoHDREnabled = false
            }
            if dev.isExposureModeSupported(.continuousAutoExposure) {
                dev.exposureMode = .continuousAutoExposure
            }
        } catch {
            // keep the defaults
        }
    }

    // MARK: - White balance and exposure

    /// nil = automatic. A number = lock the camera's white balance so that light of that temperature looks neutral.
    func setWhiteBalance(kelvin: Double?) {
        sessionQueue.async { [weak self] in
            guard let self = self, let dev = self.device else { return }
            do {
                try dev.lockForConfiguration()
                defer { dev.unlockForConfiguration() }
                if let k = kelvin, dev.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                    let temp = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(k), tint: 0)
                    let gains = self.clamped(dev.deviceWhiteBalanceGains(for: temp), for: dev)
                    dev.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                    DispatchQueue.main.async { self.lockedKelvin = k }
                } else if dev.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    dev.whiteBalanceMode = .continuousAutoWhiteBalance
                    DispatchQueue.main.async { self.lockedKelvin = nil }
                }
            } catch {
                // leave it as it was
            }
        }
    }

    /// The camera throws an exception if any gain is outside 1...maxWhiteBalanceGain, so always clamp.
    private func clamped(_ g: AVCaptureDevice.WhiteBalanceGains, for dev: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        let top = dev.maxWhiteBalanceGain
        var out = g
        out.redGain = max(1, min(g.redGain, top))
        out.greenGain = max(1, min(g.greenGain, top))
        out.blueGain = max(1, min(g.blueGain, top))
        return out
    }

    private func gainsAreValid(_ g: AVCaptureDevice.WhiteBalanceGains, for dev: AVCaptureDevice) -> Bool {
        let top = dev.maxWhiteBalanceGain
        return g.redGain >= 1 && g.redGain <= top && g.greenGain >= 1 && g.greenGain <= top && g.blueGain >= 1 && g.blueGain <= top
    }

    /// Freeze the exposure so brightness changes don't shift how colours are rendered.
    func setExposureLocked(_ locked: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self, let dev = self.device else { return }
            self.userLocksExposure = locked
            do {
                try dev.lockForConfiguration()
                defer { dev.unlockForConfiguration() }
                if locked && dev.isExposureModeSupported(.locked) {
                    dev.exposureMode = .locked
                    DispatchQueue.main.async { self.exposureLocked = true }
                } else if dev.isExposureModeSupported(.continuousAutoExposure) {
                    dev.exposureMode = .continuousAutoExposure
                    DispatchQueue.main.async { self.exposureLocked = false }
                }
            } catch {
                // leave it as it was
            }
            if !locked {
                self.lastMeteredPoint = CGPoint(x: -1, y: -1)      // meter on the square again
                self.meterExposure(atNormalizedPoint: nil)
            }
        }
    }

    /// Hold the exposure still for the 3 seconds of a Measure (so brightness can't shift mid-average), then let it follow again.
    func freezeExposure(_ freeze: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self, let dev = self.device else { return }
            self.exposureFrozenForMeasure = freeze
            if self.userLocksExposure { return }                    // already held by the user
            do {
                try dev.lockForConfiguration()
                defer { dev.unlockForConfiguration() }
                if freeze {
                    if dev.isExposureModeSupported(.locked) { dev.exposureMode = .locked }
                } else if dev.isExposureModeSupported(.continuousAutoExposure) {
                    dev.exposureMode = .continuousAutoExposure
                }
            } catch {
                // leave it as it was
            }
        }
    }

    /// Automatic exposure normally judges the whole picture. Point it at the white square instead, so the card is
    /// exposed well whatever is around it. Pass nil to use the square's current position. Runs on the session queue.
    private func meterExposure(atNormalizedPoint point: CGPoint?) {
        sessionQueue.async { [weak self] in
            guard let self = self, let dev = self.device else { return }
            guard !self.userLocksExposure, !self.exposureFrozenForMeasure else { return }
            guard dev.isExposurePointOfInterestSupported else { return }
            let rect = self.currentRect()
            let raw = point ?? CGPoint(x: rect.midX, y: rect.midY)
            let p = CGPoint(x: min(max(raw.x, 0.05), 0.95), y: min(max(raw.y, 0.05), 0.95))
            if abs(p.x - self.lastMeteredPoint.x) < 0.01 && abs(p.y - self.lastMeteredPoint.y) < 0.01 { return }
            do {
                try dev.lockForConfiguration()
                defer { dev.unlockForConfiguration() }
                dev.exposurePointOfInterest = p
                if dev.isExposureModeSupported(.continuousAutoExposure) { dev.exposureMode = .continuousAutoExposure }
                self.lastMeteredPoint = p
            } catch {
                // keep metering where it was
            }
        }
    }

    // MARK: - Card mode

    /// Card mode: instead of a fixed white balance, keep adjusting it until whatever is in the white square looks
    /// neutral grey, then read the colour temperature from Apple's own calibration of those gains.
    /// How readings are produced:
    /// .off   - Manual mode: the app works the colour temperature out from the picture itself.
    /// .scene - the camera's own automatic white balance estimate for whatever it is pointed at (nothing is adjusted).
    /// .card  - the app adjusts white balance until the card in the square looks neutral, then reads the temperature.
    enum ReadMode { case off, scene, card }

    func setReadMode(_ mode: ReadMode) {
        flagLock.lock()
        readModeFlag = mode
        flagLock.unlock()
    }

    private var readMode: ReadMode {
        flagLock.lock()
        defer { flagLock.unlock() }
        return readModeFlag
    }

    private func applyGains(_ gains: AVCaptureDevice.WhiteBalanceGains) {
        sessionQueue.async { [weak self] in
            guard let self = self, let dev = self.device, dev.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
            do {
                try dev.lockForConfiguration()
                defer { dev.unlockForConfiguration() }
                dev.setWhiteBalanceModeLocked(with: self.clamped(gains, for: dev), completionHandler: nil)
            } catch {
                // try again on the next reading
            }
        }
    }

    /// Green-versus-magenta shift of the light, in percent (positive = toward green). Compares the gains that make
    /// the card neutral with the gains for a light of the same temperature that has no tint.
    private func tintPercent(for gains: AVCaptureDevice.WhiteBalanceGains, temperature: Float, device dev: AVCaptureDevice) -> Double {
        let t = min(max(temperature, 2500), 8000)
        let locus = dev.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: t, tint: 0))
        guard gainsAreValid(locus, for: dev) else { return 0 }
        func greenBias(_ g: AVCaptureDevice.WhiteBalanceGains) -> Double {
            Double(g.greenGain) / (Double(g.redGain) * Double(g.blueGain)).squareRoot()
        }
        // a light with a green cast needs LESS green gain than a clean light of the same temperature
        return -log(greenBias(gains) / greenBias(locus)) * 100
    }

    /// One step of card mode. Returns the camera's own reading for the gains in use now, and how neutral the card looks.
    private func cardStep(_ dev: AVCaptureDevice, _ lin: RGB, clipped: Bool, adjust: Bool) -> (kelvin: Double?, tint: Double, error: Double?) {
        let gains = dev.deviceWhiteBalanceGains
        guard gainsAreValid(gains, for: dev) else { return (nil, 0, nil) }
        let tt = dev.temperatureAndTintValues(for: gains)
        let kelvin = min(max(Double(tt.temperature), 1500), 12000)
        let tint = tintPercent(for: gains, temperature: tt.temperature, device: dev)

        // Scene mode just reports the camera's own estimate
        guard adjust else { return (kelvin, tint, nil) }

        // too dark or blown out to judge the colour: report, but don't adjust
        guard lin.r > 0.004, lin.g > 0.004, lin.b > 0.004, !clipped else { return (kelvin, tint, nil) }

        // In linear light a neutral card has equal red, green and blue. If red is low, raise the red gain, and so on.
        let toRed = lin.g / lin.r, toBlue = lin.g / lin.b
        let error = max(abs(toRed - 1), abs(toBlue - 1))

        let now = CFAbsoluteTimeGetCurrent()
        if error > 0.01, !exposureFrozenForMeasure, now - lastServoTime >= 0.3 {
            let damping = 0.7
            var next = gains
            next.redGain = gains.redGain * Float(1 + damping * (toRed - 1))
            next.blueGain = gains.blueGain * Float(1 + damping * (toBlue - 1))
            let low = min(next.redGain, next.greenGain, next.blueGain)      // gains are always >= 1 with the smallest at 1
            if low > 0 {
                next.redGain /= low; next.greenGain /= low; next.blueGain /= low
            }
            lastServoTime = now
            applyGains(next)
        }
        return (kelvin, tint, error)
    }

    // MARK: - Measure square

    /// `rect` is in the camera's own 0-1 coordinates (see CameraPreview).
    func setMeasureRect(_ rect: CGRect) {
        roiLock.lock()
        roi = rect
        roiLock.unlock()
        meterExposure(atNormalizedPoint: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func currentRect() -> CGRect {
        roiLock.lock()
        defer { roiLock.unlock() }
        return roi
    }

    // MARK: - Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSampleTime >= 0.1 else { return }          // about 10 readings a second is plenty
        lastSampleTime = now

        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }

        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)
        guard let base = CVPixelBufferGetBaseAddress(pixels), width > 1, height > 1 else { return }

        let rect = currentRect()
        let x0 = max(0, min(width - 1, Int(rect.minX * CGFloat(width))))
        let x1 = max(x0 + 1, min(width, Int(rect.maxX * CGFloat(width))))
        let y0 = max(0, min(height - 1, Int(rect.minY * CGFloat(height))))
        let y1 = max(y0 + 1, min(height, Int(rect.maxY * CGFloat(height))))
        let step = max(1, min(x1 - x0, y1 - y0) / 32)              // look at roughly 32 x 32 pixels

        let table = Self.linearTable
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0, blownOut = 0.0
        var y = y0
        while y < y1 {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            var x = x0
            while x < x1 {
                let p = row + x * 4                                // BGRA
                let blue = p[0], green = p[1], red = p[2]
                r += table[Int(red)]; g += table[Int(green)]; b += table[Int(blue)]
                count += 1
                if red >= 250 || green >= 250 || blue >= 250 { blownOut += 1 }
                x += step
            }
            y += step
        }
        guard count > 0 else { return }

        let average = RGB(r: r / count, g: g / count, b: b / count)
        let clipped = blownOut / count > 0.1

        var autoK: Double?
        var cardK: Double?
        var cardTint = 0.0
        var neutralError: Double?
        if let dev = device {
            let mode = readMode
            if mode != .off {
                let step = cardStep(dev, average, clipped: clipped, adjust: mode == .card)
                cardK = step.kelvin; cardTint = step.tint; neutralError = step.error
            } else if dev.whiteBalanceMode != .locked {
                // While white balance is automatic, also note what temperature the camera itself believes.
                let gains = dev.deviceWhiteBalanceGains
                if gainsAreValid(gains, for: dev) {
                    autoK = Double(dev.temperatureAndTintValues(for: gains).temperature)
                }
            }
        }

        var sceneEV: Double?
        if let dev = device {
            let seconds = CMTimeGetSeconds(dev.exposureDuration)
            if seconds > 0, dev.iso > 0, dev.lensAperture > 0 {
                // the camera's exposure includes any bias we asked for; take it back out to get the scene's own brightness
                sceneEV = ExposureMath.sceneEV(aperture: Double(dev.lensAperture), shutterSeconds: seconds, iso: Double(dev.iso))
                    + Double(dev.exposureTargetBias)
            }
        }

        let sample = CameraSample(linear: average, clipped: clipped, autoKelvin: autoK,
                                  cardKelvin: cardK, cardTintPercent: cardTint, neutralError: neutralError,
                                  sceneEV: sceneEV)
        DispatchQueue.main.async { [weak self] in
            self?.onSample?(sample)
            self?.samples.send(sample)
        }
    }
}
