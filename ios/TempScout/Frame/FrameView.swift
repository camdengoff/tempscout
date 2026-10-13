import SwiftUI
import TempScoutCore

private struct FramePanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 360
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The ND page: the live camera with another camera's frame drawn over it, and the exposure previewed with your ND filter.
struct FrameView: View {
    @EnvironmentObject var plan: FramePlanModel
    @EnvironmentObject var live: FrameLiveModel
    @EnvironmentObject var meter: MeterViewModel

    @State private var section = 0
    @State private var panelHeight: CGFloat = 360
    @State private var showCustom = false

    private var camera: CameraController { meter.camera }

    var body: some View {
        GeometryReader { outer in
            let width = outer.size.width
            let height = max(200, outer.size.height - panelHeight)
            let zoomTarget = desiredZoom(width: width, height: height)
            VStack(spacing: 0) {
                viewport(width: width, height: height)
                panel
                    .background(GeometryReader { g in Color.clear.preference(key: FramePanelHeightKey.self, value: g.size.height) })
            }
            .onPreferenceChange(FramePanelHeightKey.self) { panelHeight = $0 }
            .onChange(of: zoomTarget) { camera.setZoom($0) }
            .onAppear { camera.setZoom(zoomTarget) }
        }
        .background(Color.black)
        .onAppear {
            camera.acquire()
            live.appear()
        }
        .onDisappear {
            live.disappear()
            camera.release()
        }
        .sheet(isPresented: $showCustom) { CustomGearSheet().environmentObject(plan) }
    }

    // MARK: - Viewport

    /// Zoom so the chosen frame fills the width of the view (the phone can only zoom in, never out).
    private func desiredZoom(width: CGFloat, height: CGFloat) -> Double {
        guard plan.settings.zoomToFrame, let finder = camera.viewfinder else { return 1 }
        let z = finder.zoomToFill(horizontalFOVDegrees: plan.horizontalFOV, viewWidth: Double(width), viewHeight: Double(height), fraction: 0.92)
        return max(1, min(camera.maxZoom, z))
    }

    private func viewport(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black
            CameraPreview(controller: camera, targetRect: .zero)
            if let finder = camera.viewfinder {
                let frameWidth = finder.points(forFOVDegrees: plan.horizontalFOV, viewWidth: Double(width), viewHeight: Double(height), zoom: camera.zoom)
                let frameHeight = finder.points(forFOVDegrees: plan.verticalFOV, viewWidth: Double(width), viewHeight: Double(height), zoom: camera.zoom)
                FrameOverlay(frame: CGSize(width: frameWidth, height: frameHeight), dim: plan.settings.dimOutside)
                if plan.horizontalFOV > finder.visibleHorizontalFOV(viewWidth: Double(width), viewHeight: Double(height), zoom: camera.zoom) + 0.5 {
                    VStack {
                        Spacer()
                        Text("Wider than this phone lens can show, so the frame is cut off")
                            .font(.footnote)
                            .foregroundColor(Theme.warm)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                }
            }
            VStack {
                hud
                Spacer()
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var hud: some View {
        VStack(spacing: 6) {
            Text("\(plan.camera.name) · \(Gear.focalLabel(plan.settings.focal)) · \(plan.aspect.name)")
                .font(.footnote.weight(.semibold))
            Text(String(format: "%.1f° × %.1f°  ·  %.0fmm full-frame equivalent", plan.horizontalFOV, plan.verticalFOV, plan.fullFrameEquivalent))
                .font(.caption)
                .foregroundColor(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 8)
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(spacing: 12) {
            Picker("", selection: $section) {
                Text("Frame").tag(0)
                Text("Exposure").tag(1)
            }
            .pickerStyle(.segmented)
            if section == 0 { frameControls } else { exposureControls }
        }
        .padding(14)
        .padding(.bottom, 4)
        .background(Color(white: 0.11))
    }

    private var frameControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Camera", selection: $plan.settings.cameraID) {
                        ForEach(plan.allCameras) { Text($0.name).tag($0.id) }
                    }
                    Button("Custom camera or lens…") { showCustom = true }
                } label: { chip("Camera", plan.camera.name) }

                Menu {
                    Picker("Lens", selection: $plan.settings.focal) {
                        ForEach(plan.focalOptions, id: \.self) { Text(Gear.focalLabel($0)).tag($0) }
                    }
                    Button("Custom camera or lens…") { showCustom = true }
                } label: { chip("Lens", Gear.focalLabel(plan.settings.focal)) }

                Menu {
                    Picker("Frame", selection: $plan.settings.aspectID) {
                        ForEach(Gear.aspects) { Text($0.name).tag($0.id) }
                    }
                } label: { chip("Frame", plan.aspect.name) }
            }
            Toggle("Zoom to fill the screen with the frame", isOn: $plan.settings.zoomToFrame)
            Toggle("Dim outside the frame", isOn: $plan.settings.dimOutside)
            Toggle("Vertical (portrait) frame", isOn: $plan.settings.vertical)
            Text("Recording areas are approximate. Use Custom to enter your exact camera.")
                .font(.caption).foregroundColor(Theme.muted)
        }
    }

    private var exposureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Frame rate", selection: $plan.settings.fps) {
                        ForEach(Gear.framesPerSecond, id: \.self) { Text(Gear.fpsLabel($0) + " fps").tag($0) }
                    }
                } label: { chip("FPS", Gear.fpsLabel(plan.settings.fps)) }
                Menu {
                    Picker("Shutter angle", selection: $plan.settings.angle) {
                        ForEach(Gear.shutterAngles, id: \.self) { Text(Gear.angleLabel($0)).tag($0) }
                    }
                } label: { chip("Shutter", Gear.angleLabel(plan.settings.angle) + " · " + plan.shutterLabel) }
                Menu {
                    Picker("ISO", selection: $plan.settings.iso) {
                        ForEach(Gear.isos, id: \.self) { Text(String(Int($0))).tag($0) }
                    }
                } label: { chip("ISO", String(Int(plan.settings.iso))) }
                Menu {
                    Picker("Aperture", selection: $plan.settings.fStop) {
                        ForEach(Gear.fStops, id: \.self) { Text(NDCalculator.apertureLabel($0)).tag($0) }
                    }
                } label: { chip("F-stop", NDCalculator.apertureLabel(plan.settings.fStop)) }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ndChip("Auto", stops: nil)
                    ForEach(Gear.ndFilters) { ndChip($0.label, stops: $0.stops) }
                }
            }

            readout
            Toggle("Preview the exposure on the picture", isOn: $plan.settings.previewExposure)
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let ev = live.sceneEV, let needed = live.ndNeeded, let error = live.exposureError {
                Text(ExposureMath.describe(error: error))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(abs(error) < 0.34 ? Theme.good : Theme.warm)
                Text(String(format: "Scene EV %.1f · needs %.1f stops of ND", ev, needed) + closestFilterText(needed))
                    .font(.footnote).foregroundColor(Theme.muted)
            } else {
                Text("Point the camera at your scene to read its brightness.")
                    .font(.footnote).foregroundColor(Theme.muted)
            }
        }
    }

    private func closestFilterText(_ needed: Double) -> String {
        guard needed > 0.15, let f = Gear.ndFilters.min(by: { abs($0.stops - needed) < abs($1.stops - needed) }) else { return "" }
        return " (closest: \(f.label))"
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10)).tracking(0.8).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6).foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func ndChip(_ title: String, stops: Double?) -> some View {
        let selected = plan.settings.ndStops == stops
        return Button { plan.settings.ndStops = stops } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selected ? .black : .white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected ? Theme.warm : Color.white.opacity(0.1), in: Capsule())
        }
    }
}

/// The frame lines: a rectangle at the true size of the chosen camera and lens, with the outside dimmed.
private struct FrameOverlay: View {
    let frame: CGSize
    let dim: Bool

    var body: some View {
        GeometryReader { g in
            let rect = CGRect(x: g.size.width / 2 - frame.width / 2, y: g.size.height / 2 - frame.height / 2,
                              width: frame.width, height: frame.height)
            ZStack {
                if dim {
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: g.size))
                        p.addRect(rect)
                    }
                    .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                }
                Path { p in p.addRect(rect) }
                    .stroke(Color.white, lineWidth: 2)
                Path { p in                                    // rule-of-thirds lines
                    for i in 1...2 {
                        let x = rect.minX + rect.width * CGFloat(i) / 3
                        let y = rect.minY + rect.height * CGFloat(i) / 3
                        p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY))
                        p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                Path { p in                                    // centre cross
                    let c = CGPoint(x: rect.midX, y: rect.midY)
                    p.move(to: CGPoint(x: c.x - 10, y: c.y)); p.addLine(to: CGPoint(x: c.x + 10, y: c.y))
                    p.move(to: CGPoint(x: c.x, y: c.y - 10)); p.addLine(to: CGPoint(x: c.x, y: c.y + 10))
                }
                .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Add your own camera (recording area in mm) or lens (focal length).
struct CustomGearSheet: View {
    @EnvironmentObject var plan: FramePlanModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var width = ""
    @State private var height = ""
    @State private var focal = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom camera") {
                    TextField("Name", text: $name)
                    TextField("Recording width (mm)", text: $width).keyboardType(.decimalPad)
                    TextField("Recording height (mm)", text: $height).keyboardType(.decimalPad)
                    Button("Add camera") {
                        if let w = Double(width), let h = Double(height), w > 0, h > 0 {
                            plan.addCustomCamera(name: name, widthMM: w, heightMM: h)
                            name = ""; width = ""; height = ""
                        }
                    }
                    Text("Use the recording area for your shooting mode (the width and height of the part of the sensor that makes the picture), from the camera's spec sheet.")
                        .font(.footnote).foregroundColor(Theme.muted)
                }
                if !plan.settings.customCameras.isEmpty {
                    Section("Your cameras") {
                        ForEach(plan.settings.customCameras) { cam in
                            Text("\(cam.name) · \(String(format: "%.1f × %.1f mm", cam.widthMM, cam.heightMM))")
                        }
                        .onDelete { plan.deleteCustomCameras(at: $0) }
                    }
                }
                Section("Custom lens") {
                    TextField("Focal length (mm)", text: $focal).keyboardType(.decimalPad)
                    Button("Use this lens") {
                        if let f = Double(focal), f > 1, f < 2000 {
                            plan.settings.focal = f
                            focal = ""
                        }
                    }
                }
            }
            .navigationTitle("Custom gear")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
