import Combine
import Foundation
import TempScoutCore

/// Live exposure on the ND page: how bright the scene is, how much ND it needs, and whether your settings would over- or
/// under-expose it. While the page is open the picture is brightened or darkened to show that.
final class FrameLiveModel: ObservableObject {
    @Published private(set) var sceneEV: Double?
    /// Stops of ND the scene needs for your camera settings (0 if none)
    @Published private(set) var ndNeeded: Double?
    /// Stops over (+) or under (-) exposed with the ND you chose
    @Published private(set) var exposureError: Double?

    private let camera: CameraController
    private let plan: FramePlanModel
    private var bag = Set<AnyCancellable>()
    private var smoothedEV: Double?
    private var appliedBias = 0.0
    private var active = false

    init(camera: CameraController, plan: FramePlanModel) {
        self.camera = camera
        self.plan = plan
        camera.samples
            .sink { [weak self] sample in self?.handle(sample) }
            .store(in: &bag)
        // recalculate when you change a setting
        plan.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &bag)
    }

    func appear() {
        active = true
        camera.meterAtCenter()
        recompute()
    }

    func disappear() {
        active = false
        smoothedEV = nil
        appliedBias = 0
        camera.setExposureBias(0)
        camera.setZoom(1)
        camera.selectCamera(.wide)             // the Meter always measures with the Wide camera
    }

    private func handle(_ sample: CameraSample) {
        guard active, let ev = sample.sceneEV else { return }
        smoothedEV = smoothedEV.map { $0 + (ev - $0) * 0.2 } ?? ev
        recompute()
    }

    private func recompute() {
        guard active, let ev = smoothedEV else { return }
        let s = plan.settings
        let t = plan.shutterSeconds
        let needed = ExposureMath.ndNeeded(sceneEV: ev, fStop: s.fStop, shutterSeconds: t, iso: s.iso)
        // Auto uses the ND the scene needs, to the nearest third of a stop (like a variable ND)
        let nd = s.ndStops ?? ((needed * 3).rounded() / 3)
        let error = ExposureMath.exposureError(sceneEV: ev, fStop: s.fStop, shutterSeconds: t, iso: s.iso, ndStops: nd)
        sceneEV = ev
        ndNeeded = needed
        exposureError = error

        // Show it on the picture: brighter when overexposed, darker when underexposed
        let target = s.previewExposure ? max(-8, min(8, error)) : 0
        if abs(target - appliedBias) > 0.1 {
            camera.setExposureBias(target)
            appliedBias = target
        }
    }
}
