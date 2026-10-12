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

    /// Called on the main thread, about 10 times a second.
    var onSample: ((CameraSample) -> Void)?

    private let sessionQueue = DispatchQueue(label: "tempscout.camera.session")
    private let sampleQueue = DispatchQueue(label: "tempscout.camera.samples")
    private var device: AVCaptureDevice?
    private var configured = false

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

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
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
        let supported = dev.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        DispatchQueue.main.async { self.whiteBalanceLockSupported = supported }
        return true
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
        }
    }

    // MARK: - Measure square

    /// `rect` is in the camera's own 0-1 coordinates (see CameraPreview).
    func setMeasureRect(_ rect: CGRect) {
        roiLock.lock()
        roi = rect
        roiLock.unlock()
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

        // While white balance is automatic, also note what temperature the camera itself believes.
        var autoK: Double?
        if let dev = device, dev.whiteBalanceMode != .locked {
            let gains = dev.deviceWhiteBalanceGains
            if gainsAreValid(gains, for: dev) {
                autoK = Double(dev.temperatureAndTintValues(for: gains).temperature)
            }
        }

        let sample = CameraSample(linear: RGB(r: r / count, g: g / count, b: b / count),
                                  clipped: blownOut / count > 0.1,
                                  autoKelvin: autoK)
        DispatchQueue.main.async { [weak self] in self?.onSample?(sample) }
    }
}
