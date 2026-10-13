import XCTest
@testable import TempScoutCore

// The expected numbers below come from running the original JavaScript web app (index.html) on the same inputs,
// so a pass here means the Swift port matches the version that was tested on a real phone.
final class ColorMathTests: XCTestCase {
    func testToLinear() {
        XCTAssertEqual(ColorMath.toLinear(0), 0, accuracy: 1e-12)
        XCTAssertEqual(ColorMath.toLinear(10), 0.003035269835488375, accuracy: 1e-12)
        XCTAssertEqual(ColorMath.toLinear(64), 0.05126945837404324, accuracy: 1e-12)
        XCTAssertEqual(ColorMath.toLinear(128), 0.21586050011389926, accuracy: 1e-12)
        XCTAssertEqual(ColorMath.toLinear(200), 0.5775804404296506, accuracy: 1e-12)
        XCTAssertEqual(ColorMath.toLinear(255), 1, accuracy: 1e-12)
    }

    func testToSRGBRoundTrips() {
        for v in [0.0, 10, 64, 128, 200, 255] {
            XCTAssertEqual(ColorMath.toSRGB(ColorMath.toLinear(v)), v, accuracy: 1e-6)
        }
    }

    func testRgbToKelvin() {
        XCTAssertEqual(ColorMath.rgbToKelvin(r: 255, g: 255, b: 255)!, 6504.203555220641, accuracy: 1e-6)
        XCTAssertEqual(ColorMath.rgbToKelvin(r: 200, g: 180, b: 150)!, 4687.124551134135, accuracy: 1e-6)
        XCTAssertEqual(ColorMath.rgbToKelvin(r: 128, g: 128, b: 128)!, 6504.203555220641, accuracy: 1e-6)
        XCTAssertEqual(ColorMath.rgbToKelvin(r: 255, g: 200, b: 120)!, 3381.263579646898, accuracy: 1e-6)
        XCTAssertEqual(ColorMath.rgbToKelvin(r: 150, g: 160, b: 200)!, 12000, accuracy: 1e-9)   // clamped
        XCTAssertNil(ColorMath.rgbToKelvin(r: 0, g: 0, b: 0))
    }
}

final class CalibrationTests: XCTestCase {
    func testTwoPointFit() {
        let pts = [CalPoint(m: 283.7228372283723, t: 370.3703703703704),
                   CalPoint(m: 168.6434721490072, t: 178.57142857142858)]
        let f = Calibration.fit(pts)
        XCTAssertEqual(f.a, 1.666666666666666, accuracy: 1e-9)
        XCTAssertEqual(f.b, -102.50102501024998, accuracy: 1e-9)
        XCTAssertEqual(f.n, 2)
    }

    /// A camera that squashes colour (slope 0.6) is recovered exactly at a light that was never calibrated.
    func testTwoPointRecoversUncalibratedLight() {
        let pts = [CalPoint(m: 283.7228372283723, t: 370.3703703703704),
                   CalPoint(m: 168.6434721490072, t: 178.57142857142858)]
        let f = Calibration.fit(pts)
        let cameraSaidK = 4974.245873648264            // what that camera reports for a true 4300K light
        let m = Calibration.calibratedMired(rawKelvin: cameraSaidK, wbOffset: 0, fit: f)
        XCTAssertEqual(1e6 / m, 4300, accuracy: 1)
    }

    func testOnePointIsAShift() {
        let f = Calibration.fit([CalPoint(m: 300, t: 250)])
        XCTAssertEqual(f.a, 1, accuracy: 1e-12)
        XCTAssertEqual(f.b, -50, accuracy: 1e-12)
    }

    func testLegacyShiftUsedWithNoPoints() {
        let f = Calibration.fit([], legacyShift: 12)
        XCTAssertEqual(f, CalFit(a: 1, b: 12, n: 0))
    }

    func testAddingReplacesSameLightAndCapsAtFour() {
        var pts = Calibration.adding(CalPoint(m: 300, t: 370), to: [])
        pts = Calibration.adding(CalPoint(m: 301, t: 372), to: pts)      // same light (within 8 mired): replaced
        XCTAssertEqual(pts.count, 1)
        for t in [200.0, 250, 300, 350, 400] { pts = Calibration.adding(CalPoint(m: t, t: t + 20), to: pts) }
        XCTAssertEqual(pts.count, Calibration.maxPoints)
    }

    func testWhiteBalanceOffset() {
        XCTAssertEqual(Calibration.wbOffsetMired(lockedKelvin: ColorMath.d65Kelvin), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(Calibration.wbOffsetMired(lockedKelvin: 3200), 0)       // warm lock -> shift warmer
    }
}

final class NDTests: XCTestCase {
    func testStops() {
        let base = Exposure(aperture: 11, shutter: 1.0 / 48, iso: 100)
        var r = NDCalculator.compute(base: base, wanted: Exposure(aperture: 2.8, shutter: 1.0 / 48, iso: 100))
        XCTAssertEqual(r.stops, 3.948009582934111, accuracy: 1e-9)
        XCTAssertEqual(r.thirdStops, 4, accuracy: 1e-9)
        XCTAssertEqual(NDCalculator.summary(r), "ND 4 (1.2)")

        r = NDCalculator.compute(base: base, wanted: Exposure(aperture: 4, shutter: 1.0 / 48, iso: 200))
        XCTAssertEqual(r.stops, 3.9188632372745946, accuracy: 1e-9)

        r = NDCalculator.compute(base: Exposure(aperture: 8, shutter: 1.0 / 125, iso: 400),
                                 wanted: Exposure(aperture: 1.8, shutter: 1.0 / 50, iso: 100))
        XCTAssertEqual(r.stops, 3.6259342817774622, accuracy: 1e-9)
        XCTAssertEqual(r.thirdStops, 3.6666666666666665, accuracy: 1e-9)
        XCTAssertEqual(NDCalculator.summary(r), "ND 3.7 (1.1)")
    }

    func testNoNDNeeded() {
        let r = NDCalculator.compute(base: Exposure(aperture: 2.8, shutter: 1.0 / 48, iso: 100),
                                     wanted: Exposure(aperture: 11, shutter: 1.0 / 48, iso: 100))
        XCTAssertEqual(r.stops, -3.948009582934111, accuracy: 1e-9)
        XCTAssertEqual(r.needed, 0)
        XCTAssertEqual(NDCalculator.summary(r), "ND 0 (0.0)")
    }

    func testLabels() {
        XCTAssertEqual(NDCalculator.apertureLabel(2), "f/2")
        XCTAssertEqual(NDCalculator.apertureLabel(2.8), "f/2.8")
        XCTAssertEqual(NDCalculator.apertureLabel(11), "f/11")
    }
}

final class SunTests: XCTestCase {
    private let lat = 40.015, lng = -105.27           // Boulder, CO

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testPosition() {
        var p = SunMath.position(date: date("2026-06-21T18:00:00Z"), latitude: lat, longitude: lng)
        XCTAssertEqual(p.azimuth, 136.60391938157966, accuracy: 1e-6)
        XCTAssertEqual(p.altitude, 68.75985625119617, accuracy: 1e-6)

        p = SunMath.position(date: date("2026-06-21T19:03:00Z"), latitude: lat, longitude: lng)       // solar noon
        XCTAssertEqual(p.azimuth, 180.02409201228522, accuracy: 1e-6)
        XCTAssertEqual(p.altitude, 73.41945356222955, accuracy: 1e-6)

        p = SunMath.position(date: date("2026-12-21T17:00:00Z"), latitude: lat, longitude: lng)
        XCTAssertEqual(p.azimuth, 150.80934128837373, accuracy: 1e-6)
        XCTAssertEqual(p.altitude, 20.731480814982586, accuracy: 1e-6)

        p = SunMath.position(date: date("2026-03-20T14:00:00Z"), latitude: lat, longitude: lng)
        XCTAssertEqual(p.azimuth, 98.36595833959774, accuracy: 1e-6)
        XCTAssertEqual(p.altitude, 9.815731474621206, accuracy: 1e-6)
    }

    func testEventsMatchWebApp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = date("2026-06-21T12:00:00Z")
        func t(_ rising: Bool, _ z: Double) -> Double? {
            SunMath.event(date: noon, latitude: lat, longitude: lng, rising: rising, zenith: z, calendar: cal)?.timeIntervalSince1970
        }
        XCTAssertEqual(t(true, 90.833)!, date("2026-06-21T11:32:15Z").timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(t(false, 90.833)!, date("2026-06-21T02:33:22Z").timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(t(true, 84)!, date("2026-06-21T12:13:02Z").timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(t(true, 96)!, date("2026-06-21T10:59:21Z").timeIntervalSince1970, accuracy: 1)
    }

    func testSunsetStaysOnLocalDay() {
        // In Denver (UTC-6 in June) sunset is about 20:33 local on the 21st, which is 02:33 UTC on the 22nd.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Denver")!
        let noonLocal = date("2026-06-21T18:00:00Z")
        let sunset = SunMath.event(date: noonLocal, latitude: lat, longitude: lng, rising: false, zenith: 90.833, calendar: cal)!
        XCTAssertTrue(cal.isDate(sunset, inSameDayAs: noonLocal))
        XCTAssertEqual(sunset.timeIntervalSince1970, date("2026-06-22T02:33:22Z").timeIntervalSince1970, accuracy: 60)
    }

    func testPolarNight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertNil(SunMath.event(date: date("2026-12-21T12:00:00Z"), latitude: 80, longitude: 0, rising: true, zenith: 90.833, calendar: cal))
    }
}

final class MeterEngineTests: XCTestCase {
    private func lin(_ v: Double) -> RGB { RGB(r: v, g: v, b: v) }

    func testSteadyAfterTenFrames() {
        let e = MeterEngine()
        for _ in 0..<12 { e.ingest(linear: lin(0.4), clipped: false) }
        XCTAssertEqual(e.quality, .steady)
        XCTAssertEqual(Double(e.live!.displayKelvin!), 6500, accuracy: 50)       // neutral grey, auto WB, no calibration
    }

    func testTooBrightAndTooDark() {
        let e = MeterEngine()
        e.ingest(linear: lin(0.4), clipped: true)
        XCTAssertEqual(e.quality, .tooBright)
        let d = MeterEngine()
        d.ingest(linear: lin(0.002), clipped: false)
        XCTAssertEqual(d.quality, .tooDark)
    }

    func testMeasureAveragesThirtyFramesThenHolds() {
        let e = MeterEngine()
        e.ingest(linear: lin(0.4), clipped: false)
        e.startMeasuring()
        XCTAssertEqual(e.progress, 0)
        for i in 0..<MeterEngine.framesPerMeasure { e.ingest(linear: lin(0.4), clipped: false); if i < 29 { XCTAssertNotNil(e.progress) } }
        XCTAssertTrue(e.isHeld)
        XCTAssertNil(e.progress)
        XCTAssertEqual(e.held!.spreadK, 0)
        if case .measured = e.quality {} else { XCTFail("expected .measured, got \(e.quality)") }
        // frames are ignored while held
        let k = e.held!.displayKelvin
        e.ingest(linear: RGB(r: 0.6, g: 0.4, b: 0.2), clipped: false)
        XCTAssertEqual(e.held!.displayKelvin, k)
        e.resume()
        XCTAssertFalse(e.isHeld)
    }

    func testWhiteBalanceLockShiftsReading() {
        let e = MeterEngine()
        e.lockedKelvin = 3200
        for _ in 0..<12 { e.ingest(linear: lin(0.4), clipped: false) }
        // a neutral grey under a 3200K lock means the light was 3200K
        XCTAssertEqual(e.live!.kelvin!, 3200, accuracy: 30)
    }

    /// Adding a calibration point while a reading is held must change that held reading straight away.
    func testAddingCalibrationUpdatesHeldReading() {
        let e = MeterEngine()
        for _ in 0..<5 { e.ingest(linear: lin(0.4), clipped: false) }
        e.startMeasuring()
        for _ in 0..<MeterEngine.framesPerMeasure { e.ingest(linear: lin(0.4), clipped: false) }
        XCTAssertTrue(e.isHeld)
        XCTAssertEqual(e.held!.kelvin!, 6504, accuracy: 5)
        let spread = e.held!.spreadK

        let measured = e.measuredMiredForCalibration()!
        e.calPoints = [CalPoint(m: measured, t: ColorMath.mired(5600))]
        e.refresh()

        XCTAssertEqual(e.held!.kelvin!, 5600, accuracy: 5)          // now shows the known light
        XCTAssertEqual(e.held!.spreadK, spread)
        XCTAssertEqual(e.uncalibratedKelvin()!, 6504, accuracy: 5)   // the raw camera value is still available
    }

    func testAddingCalibrationUpdatesLiveReading() {
        let e = MeterEngine()
        for _ in 0..<12 { e.ingest(linear: lin(0.4), clipped: false) }
        let measured = e.measuredMiredForCalibration()!
        e.calPoints = [CalPoint(m: measured, t: ColorMath.mired(3000))]
        e.refresh()
        XCTAssertEqual(e.live!.kelvin!, 3000, accuracy: 5)
    }

    func testCalibrationPointsApply() {
        let e = MeterEngine()
        e.calPoints = [CalPoint(m: ColorMath.mired(6504), t: ColorMath.mired(5600))]
        for _ in 0..<12 { e.ingest(linear: lin(0.4), clipped: false) }
        XCTAssertEqual(e.live!.kelvin!, 5600, accuracy: 30)
    }
}

final class CardModeTests: XCTestCase {
    private func lin(_ v: Double) -> RGB { RGB(r: v, g: v, b: v) }

    /// In card mode the number is the camera's own: no colour maths, no white balance offset.
    func testCardReadingIsTheCamerasKelvin() {
        let e = MeterEngine()
        for _ in 0..<12 { e.ingestCard(kelvin: 4000, tintPercent: 1.5, neutralError: 0.005, linear: lin(0.4), clipped: false) }
        XCTAssertEqual(e.live!.kelvin!, 4000, accuracy: 1)
        XCTAssertEqual(e.live!.tint, 1.5, accuracy: 1e-9)
        XCTAssertEqual(e.quality, .steady)
    }

    func testStillAdjustingShowsSettling() {
        let e = MeterEngine()
        for _ in 0..<12 { e.ingestCard(kelvin: 4000, tintPercent: 0, neutralError: 0.2, linear: lin(0.4), clipped: false) }
        XCTAssertEqual(e.quality, .settling)
    }

    func testCardMeasureAveragesAndHolds() {
        let e = MeterEngine()
        e.ingestCard(kelvin: 3000, tintPercent: 0, neutralError: 0, linear: lin(0.4), clipped: false)
        e.startMeasuring()
        for i in 0..<MeterEngine.framesPerMeasure {
            // 29 frames at 3000K and one outlier; the average sits between
            e.ingestCard(kelvin: i == 0 ? 3600 : 3000, tintPercent: 2, neutralError: 0, linear: lin(0.4), clipped: false)
        }
        XCTAssertTrue(e.isHeld)
        XCTAssertGreaterThan(e.held!.kelvin!, 2950)
        XCTAssertLessThan(e.held!.kelvin!, 3100)
        XCTAssertEqual(e.held!.tint, 2, accuracy: 1e-9)
        XCTAssertNotNil(e.held!.spreadK)
        e.resume()
        XCTAssertFalse(e.isHeld)
    }

    func testCalibrationAppliesToCameraKelvin() {
        let e = MeterEngine()
        for _ in 0..<12 { e.ingestCard(kelvin: 5200, tintPercent: 0, neutralError: 0, linear: lin(0.4), clipped: false) }
        let measured = e.measuredMiredForCalibration()!
        XCTAssertEqual(1e6 / measured, 5200, accuracy: 1)                         // raw camera value, uncalibrated
        e.calPoints = [CalPoint(m: measured, t: ColorMath.mired(5600))]            // the light was really 5600K
        e.refresh()
        XCTAssertEqual(e.live!.kelvin!, 5600, accuracy: 1)
        XCTAssertEqual(e.uncalibratedKelvin()!, 5200, accuracy: 1)
    }

    func testResetClearsEverything() {
        let e = MeterEngine()
        for _ in 0..<12 { e.ingestCard(kelvin: 5200, tintPercent: 0, neutralError: 0, linear: lin(0.4), clipped: false) }
        e.reset()
        XCTAssertNil(e.live)
        XCTAssertNil(e.measuredMiredForCalibration())
        XCTAssertEqual(e.quality, .waiting)
    }
}

final class FramingTests: XCTestCase {
    func testFieldOfView() {
        XCTAssertEqual(Framing.fieldOfView(sizeMM: 36, focalMM: 50), 39.597752709049864, accuracy: 1e-9)
        XCTAssertEqual(Framing.fieldOfView(sizeMM: 36, focalMM: 24), 73.73979529168804, accuracy: 1e-9)
        XCTAssertEqual(Framing.fieldOfView(sizeMM: 24, focalMM: 50), 26.991466561591622, accuracy: 1e-9)
        XCTAssertEqual(Framing.fieldOfView(sizeMM: 36, focalMM: 135), 15.18928673718289, accuracy: 1e-9)
    }

    func testFrameShapes() {
        var f = Framing.frame(widthMM: 36, heightMM: 24, aspect: 2.39)          // wider: full width
        XCTAssertEqual(f.width, 36, accuracy: 1e-9)
        XCTAssertEqual(f.height, 15.06276150627615, accuracy: 1e-9)
        f = Framing.frame(widthMM: 36, heightMM: 24, aspect: 1.0)               // narrower: full height
        XCTAssertEqual(f.width, 24, accuracy: 1e-9)
        XCTAssertEqual(f.height, 24, accuracy: 1e-9)
        f = Framing.frame(widthMM: 36, heightMM: 24, aspect: 16.0 / 9.0)
        XCTAssertEqual(f.width, 36, accuracy: 1e-9)
        XCTAssertEqual(f.height, 20.25, accuracy: 1e-9)
        f = Framing.frame(widthMM: 36, heightMM: 24, aspect: 9.0 / 16.0)
        XCTAssertEqual(f.width, 13.5, accuracy: 1e-9)
        XCTAssertEqual(f.height, 24, accuracy: 1e-9)
        f = Framing.frame(widthMM: 36, heightMM: 24, aspect: nil)
        XCTAssertEqual(f.width, 36)
        XCTAssertEqual(f.height, 24)
    }

    func testEquivalentFocalLength() {
        XCTAssertEqual(Framing.fullFrameEquivalent(focalMM: 50, diagonalMM: CameraFormat(id: "x", name: "x", widthMM: 36, heightMM: 24).diagonalMM), 50, accuracy: 0.05)
        let bmpcc = Gear.cameras.first { $0.id == "bmpcc-6k" }!
        XCTAssertEqual(Framing.fullFrameEquivalent(focalMM: 50, diagonalMM: bmpcc.diagonalMM), 81.62927675368938, accuracy: 0.01)
    }

    func testGearListsAreSane() {
        XCTAssertTrue(Gear.cameras.contains { $0.id == Gear.defaultCameraID })
        XCTAssertEqual(Set(Gear.cameras.map { $0.id }).count, Gear.cameras.count)       // unique ids
        XCTAssertTrue(Gear.cameras.allSatisfy { $0.widthMM > 0 && $0.heightMM > 0 })
        XCTAssertEqual(Gear.ndFilters.first?.label, "Clear")
        XCTAssertEqual(Gear.ndFilters.first { $0.stops == 3 }?.label, "ND 0.9")
        XCTAssertEqual(Gear.ndFilters.first { $0.stops == 10 }?.label, "ND 3.0")
    }

    // iPhone-like numbers: 70 degree long side, 1920 x 1080 frame, shown in a 393 x 500 view
    private let phone = Viewfinder(longFOVDegrees: 70, longPixels: 1920, shortPixels: 1080)

    func testViewfinderGeometry() {
        XCTAssertEqual(phone.focalPixels(), 1371.0220864724301, accuracy: 1e-6)
        XCTAssertEqual(phone.pointsPerPixel(viewWidth: 393, viewHeight: 500), 0.3638888888888889, accuracy: 1e-12)
        XCTAssertEqual(phone.visibleHorizontalFOV(viewWidth: 393, viewHeight: 500), 42.99566141876366, accuracy: 1e-6)
    }

    func testFrameSizeOnScreen() {
        let w = phone.points(forFOVDegrees: 39.5978, viewWidth: 393, viewHeight: 500)
        XCTAssertEqual(w, 359.20825180617965, accuracy: 0.01)
        // a frame exactly as wide as the phone shows fills the view width
        let visible = phone.visibleHorizontalFOV(viewWidth: 393, viewHeight: 500)
        XCTAssertEqual(phone.points(forFOVDegrees: visible, viewWidth: 393, viewHeight: 500), 393, accuracy: 1e-6)
        // zooming in makes everything bigger in proportion
        let z2 = phone.points(forFOVDegrees: 39.5978, viewWidth: 393, viewHeight: 500, zoom: 2)
        XCTAssertEqual(z2, 2 * w, accuracy: 1e-6)
    }

    func testZoomToFill() {
        let z = phone.zoomToFill(horizontalFOVDegrees: 39.5978, viewWidth: 393, viewHeight: 500, fraction: 0.9)
        XCTAssertEqual(z, 0.9846655755303979, accuracy: 1e-6)
        let width = phone.points(forFOVDegrees: 39.5978, viewWidth: 393, viewHeight: 500, zoom: z)
        XCTAssertEqual(width, 0.9 * 393, accuracy: 1e-6)
    }
}

final class ExposureMathTests: XCTestCase {
    func testSceneEV() {
        // "Sunny 16": f/16 at 1/100 s, ISO 100 is about EV 14.6
        XCTAssertEqual(ExposureMath.sceneEV(aperture: 16, shutterSeconds: 0.01, iso: 100), 14.643856189774725, accuracy: 1e-9)
    }

    func testShutter() {
        XCTAssertEqual(ExposureMath.shutterSeconds(angle: 180, fps: 24), 1.0 / 48, accuracy: 1e-12)
        XCTAssertEqual(ExposureMath.shutterSeconds(angle: 172.8, fps: 24), 0.02, accuracy: 1e-12)
        XCTAssertEqual(ExposureMath.shutterSeconds(angle: 90, fps: 25), 0.01, accuracy: 1e-12)
        XCTAssertEqual(ExposureMath.shutterSeconds(angle: 360, fps: 30), 1.0 / 30, accuracy: 1e-12)
    }

    func testNDNeededAndError() {
        let scene = 14.643856189774725                       // bright sun
        let t = 1.0 / 48
        XCTAssertEqual(ExposureMath.evForSettings(fStop: 2.8, shutterSeconds: t, iso: 800, ndStops: 0), 5.55581615506164, accuracy: 1e-9)
        XCTAssertEqual(ExposureMath.ndNeeded(sceneEV: scene, fStop: 2.8, shutterSeconds: t, iso: 800), 9.088040034713085, accuracy: 1e-9)
        // with a 9 stop ND (ND 2.7) it is almost exactly right: 0.09 stops over
        XCTAssertEqual(ExposureMath.exposureError(sceneEV: scene, fStop: 2.8, shutterSeconds: t, iso: 800, ndStops: 9), 0.08804003471308519, accuracy: 1e-9)
        // with no ND it is about 9 stops over
        XCTAssertEqual(ExposureMath.exposureError(sceneEV: scene, fStop: 2.8, shutterSeconds: t, iso: 800, ndStops: 0), 9.088040034713085, accuracy: 1e-9)
        // a dim scene needs no ND
        XCTAssertEqual(ExposureMath.ndNeeded(sceneEV: 3, fStop: 2.8, shutterSeconds: t, iso: 800), 0)
    }

    func testDescribe() {
        XCTAssertEqual(ExposureMath.describe(error: 0.1), "Correct")
        XCTAssertEqual(ExposureMath.describe(error: 1.33), "+1.3 stops over")
        XCTAssertEqual(ExposureMath.describe(error: -2.0), "-2.0 stops under")
    }
}

final class LensPlannerTests: XCTestCase {
    // iPhone-like cameras (angle of view along the long side of a 1920 x 1080 frame), shown in a 393 x 400 view
    private let ultra = LensCandidate(id: "ultraWide", viewfinder: Viewfinder(longFOVDegrees: 106, longPixels: 1920, shortPixels: 1080))
    private let wide = LensCandidate(id: "wide", viewfinder: Viewfinder(longFOVDegrees: 67, longPixels: 1920, shortPixels: 1080))
    private let tele = LensCandidate(id: "telephoto", viewfinder: Viewfinder(longFOVDegrees: 24, longPixels: 1920, shortPixels: 1080))

    private func pick(_ frame: Double, _ cams: [LensCandidate]) -> String? {
        LensPlanner.bestCamera(horizontalFOV: frame, candidates: cams, viewWidth: 393, viewHeight: 400)
    }

    func testVisibleFieldsOfView() {
        XCTAssertEqual(ultra.viewfinder.visibleHorizontalFOV(viewWidth: 393, viewHeight: 400), 73.48, accuracy: 0.01)
        XCTAssertEqual(wide.viewfinder.visibleHorizontalFOV(viewWidth: 393, viewHeight: 400), 40.84, accuracy: 0.01)
        XCTAssertEqual(tele.viewfinder.visibleHorizontalFOV(viewWidth: 393, viewHeight: 400), 13.64, accuracy: 0.01)
    }

    func testPicksTheNarrowestCameraThatStillCoversTheFrame() {
        let all = [ultra, wide, tele]
        XCTAssertEqual(pick(10, all), "telephoto")      // fits inside the telephoto's view
        XCTAssertEqual(pick(20, all), "wide")           // too wide for the telephoto, so wide with a digital crop
        XCTAssertEqual(pick(30, all), "wide")
        XCTAssertEqual(pick(40, all), "ultraWide")      // just wider than the wide camera can show
        XCTAssertEqual(pick(60, all), "ultraWide")
    }

    func testFrameWiderThanEveryCameraUsesTheWidest() {
        XCTAssertEqual(pick(100, [ultra, wide, tele]), "ultraWide")
        XCTAssertEqual(pick(100, [wide, tele]), "wide")
    }

    func testPhonesWithFewerCameras() {
        XCTAssertEqual(pick(10, [ultra, wide]), "wide")        // no telephoto: crop the wide camera instead
        XCTAssertEqual(pick(50, [wide]), "wide")
        XCTAssertNil(pick(30, []))
    }
}

