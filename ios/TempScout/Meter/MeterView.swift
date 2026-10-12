import SwiftUI
import TempScoutCore

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Full-screen camera with a frosted control panel over it.
struct MeterView: View {
    @EnvironmentObject var vm: MeterViewModel
    @EnvironmentObject var nd: NDModel
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: ShotStore

    @State private var panelHeight: CGFloat = 400
    @State private var showSettings = false
    @State private var toast: String?

    private static let areaChoices: [Double] = [0.1, 0.2, 0.35, 0.5]
    private static let kelvinFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    var body: some View {
        GeometryReader { outer in
            let compact = outer.size.height < 700
            let side = vm.areaFraction * outer.size.width
            let centerY = squareCenterY(height: outer.size.height)
            ZStack(alignment: .bottom) {
                CameraPreview(controller: vm.camera,
                              targetRect: CGRect(x: outer.size.width / 2 - side / 2,
                                                 y: outer.safeAreaInsets.top + centerY - side / 2,
                                                 width: side, height: side))
                    .ignoresSafeArea()

                cameraMessage

                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: side, height: side)
                    .position(x: outer.size.width / 2, y: centerY)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    hud
                    Spacer()
                }

                panel(compact: compact)
            }
        }
        .overlay(alignment: .top) { toastView }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(vm).environmentObject(library) }
        .onAppear { vm.camera.start() }
        .onDisappear { vm.camera.stop() }
    }

    /// The measure square sits in the free space between the status pill and the panel.
    private func squareCenterY(height: CGFloat) -> CGFloat {
        let top: CGFloat = 70
        let bottom = height - panelHeight - 12
        return max(top + 40, top + (bottom - top) / 2)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var cameraMessage: some View {
        switch vm.camera.status {
        case .denied:
            messageCard("TempScout needs the camera to read the light.", button: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        case .failed(let text):
            messageCard(text, button: "Try again") { vm.camera.start() }
        default:
            EmptyView()
        }
    }

    private func messageCard(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Text(text).multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 200)
    }

    private var hud: some View {
        VStack(spacing: 8) {
            HStack {
                Text("TempScout").font(.headline).shadow(radius: 4)
                Spacer()
            }
            Text(MeterViewModel.qualityText(vm.quality))
                .font(.footnote)
                .foregroundColor(qualityColor)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var qualityColor: Color {
        switch vm.quality {
        case .steady, .measured: return Theme.good
        case .tooBright, .tooDark, .moving, .noisy: return Theme.warm
        default: return .white
        }
    }

    private func panel(compact: Bool) -> some View {
        VStack(spacing: 0) {
            toolbar
            line
            bigReadout(compact: compact)
            line
            ndRow
            if !compact {
                line
                chips
            }
            line
            kelvinScale
            line
            tintScale
            line
            shutterRow
        }
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(GeometryReader { g in Color.clear.preference(key: PanelHeightKey.self, value: g.size.height) })
        .onPreferenceChange(PanelHeightKey.self) { panelHeight = $0 }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var line: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolButton("viewfinder") {
                let next = Self.areaChoices.first(where: { $0 > vm.areaFraction + 0.001 }) ?? Self.areaChoices[0]
                vm.areaFraction = next
                show("Measure area \(Int((next * 100).rounded()))%")
            }
            toolButton("circle") {
                guard vm.reading?.displayKelvin != nil else { return show("Start the camera first") }
                vm.setReferenceFromReading()
                show("Reference set to \(vm.referenceKelvin ?? 0)K")
            }
            toolButton("bookmark") {
                guard let shot = vm.makeShot(note: "") else { return show("Nothing to save yet") }
                library.add(shot)
                show("Saved to library")
            }
            toolButton("slider.horizontal.3") { showSettings = true }
        }
        .background(Color.black.opacity(0.12))
    }

    private func toolButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
    }

    private func bigReadout(compact: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(kelvinText)
                    .font(.system(size: compact ? 52 : 70, weight: .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tintText)
                        .font(.system(size: 21, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Color.white.opacity(0.8))
                    Text(tintSubtitle).font(.system(size: 10)).foregroundColor(Theme.muted)
                }
            }
            Text(descriptionText)
                .font(.footnote)
                .foregroundColor(Color.white.opacity(0.75))
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private var ndRow: some View {
        let result = nd.result
        return Button { app.tab = .nd } label: {
            HStack(spacing: 10) {
                Text(NDCalculator.summary(result))
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .padding(.trailing, 10)
                    .overlay(Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1), alignment: .trailing)
                stat("Shutter", NDCalculator.shutterLabel(nd.wanted.shutter))
                stat("ISO", NDCalculator.isoLabel(nd.wanted.iso))
                stat("F-stop", NDCalculator.apertureLabel(nd.wanted.aperture))
                Image(systemName: "chevron.right").font(.footnote).foregroundColor(Theme.muted)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }

    private var chips: some View {
        HStack {
            stat("Bright", vm.reading.map { "\(Int(($0.luminance * 100).rounded()))%" } ?? "—")
            stat("WB", vm.cardMode ? "Card" : (vm.lockedKelvin.map { "\(Int($0))K" } ?? "Auto"))
            stat("Cal", vm.calPoints.isEmpty ? "None" : "\(vm.calPoints.count) pt" + (vm.calPoints.count > 1 ? "s" : ""))
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(title.uppercased()).font(.system(size: 10)).tracking(0.8).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var kelvinScale: some View {
        let k = vm.reading?.kelvin ?? 5000
        return GradientScale(labels: ["2,000", "3,000", "4,000", "5,000", "6,000", "7,000", "8,000"],
                             colors: [Color(red: 1, green: 0.48, blue: 0.09), Color(red: 1, green: 0.76, blue: 0.48),
                                      Color(red: 0.96, green: 0.95, blue: 0.92), Color(red: 0.61, green: 0.76, blue: 1),
                                      Color(red: 0.18, green: 0.48, blue: 1)],
                             position: (max(2000, min(8000, k)) - 2000) / 6000,
                             active: vm.reading?.kelvin != nil)
    }

    private var tintScale: some View {
        let t = vm.reading?.tint ?? 0
        return GradientScale(labels: ["G+10", "G+5", "0", "M-5", "M-10"],
                             colors: [Color(red: 0.66, green: 0.94, blue: 0.66), Color(red: 0.91, green: 0.97, blue: 0.89),
                                      Color(red: 0.94, green: 0.71, blue: 0.91)],
                             position: 0.5 - max(-10, min(10, t)) / 20,
                             active: vm.reading != nil)
    }

    private var shutterRow: some View {
        HStack {
            if vm.cardMode {
                // Card mode needs no lock: the app adjusts white balance to the card by itself
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                Button {
                    vm.setWhiteBalanceLock(vm.lockedKelvin == nil)
                    show(vm.lockedKelvin == nil ? "White balance locked at \(Int(vm.wbKelvin))K" : "White balance: auto")
                } label: {
                    Image(systemName: vm.lockedKelvin == nil ? "lock.open" : "lock.fill")
                        .font(.system(size: 22))
                        .foregroundColor(vm.lockedKelvin == nil ? .white : Theme.warm)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .disabled(!vm.camera.whiteBalanceLockSupported)
            }

            Button { vm.toggleMeasure() } label: { shutter }

            Text(shutterLabel)
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.12))
    }

    private var shutter: some View {
        let fraction = Double(vm.progress ?? 0) / Double(MeterEngine.framesPerMeasure)
        return ZStack {
            Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 66, height: 66)
            Circle().fill(vm.isHeld || vm.progress != nil ? Theme.warm : Color.white).frame(width: 52, height: 52)
            if vm.progress != nil {
                Circle().trim(from: 0, to: fraction)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 66, height: 66)
            }
        }
    }

    private var shutterLabel: String {
        if vm.isHeld { return "Resume" }
        if let p = vm.progress { return "Measuring \(max(0, Int(ceil(Double(MeterEngine.framesPerMeasure - p) / 10))))s" }
        return "Measure"
    }

    // MARK: - Text

    private var kelvinText: String {
        guard let k = vm.reading?.displayKelvin else { return "—" }
        return (Self.kelvinFormatter.string(from: NSNumber(value: k)) ?? "\(k)") + "K"
    }

    private var tintText: String {
        guard let t = vm.reading?.tint else { return "—" }
        if abs(t) < 0.8 { return "Neutral" }
        return (t > 0 ? "+" : "") + String(format: "%.1f", t)
    }

    private var tintSubtitle: String {
        guard let t = vm.reading?.tint, abs(t) >= 0.8 else { return " " }
        return t > 0 ? "toward green" : "toward magenta"
    }

    private var descriptionText: String {
        guard let r = vm.reading, let k = r.kelvin else { return "Kelvin" }
        var parts = [ColorMath.lightName(k)]
        if let s = r.spreadK, s > 0 { parts.append("±\(s)K") }
        if let ref = vm.referenceKelvin, let now = r.displayKelvin {
            let d = now - ref
            parts.append("Δ \(d > 0 ? "+" : "")\(d)K vs ref")
        }
        return parts.joined(separator: " · ")
    }

    private func show(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if toast == text { toast = nil } }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = toast {
            Text(toast)
                .font(.subheadline)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Color.black.opacity(0.8), in: Capsule())
                .padding(.top, 60)
                .transition(.opacity)
        }
    }
}

/// A coloured bar with tick labels above it and a round knob on it.
private struct GradientScale: View {
    let labels: [String]
    let colors: [Color]
    let position: Double          // 0...1
    var active = true

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                    if i < labels.count - 1 { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundColor(Color.white.opacity(0.75))

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 5)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .opacity(active ? 1 : 0.5)
                        .offset(x: max(0, min(1, position)) * g.size.width - 11)
                        .animation(.linear(duration: 0.12), value: position)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 22)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

// MARK: - Settings

struct SettingsSheet: View {
    @EnvironmentObject var vm: MeterViewModel
    @EnvironmentObject var library: ShotStore
    @Environment(\.dismiss) private var dismiss
    @State private var knownKelvin = ""
    @State private var note = ""
    @State private var message: String?

    private var fitDescription: String {
        guard !vm.calPoints.isEmpty else { return "No calibration yet: the two numbers above are the same." }
        let f = Calibration.fit(vm.calPoints)
        return String(format: "Fit from %d point%@: slope %.2f, shift %+.0f mired.", f.n, f.n == 1 ? "" : "s", f.a, f.b)
    }

    /// Manual mode only: lock the camera's white balance by hand.
    @ViewBuilder
    private var whiteBalanceControls: some View {
        if vm.camera.whiteBalanceLockSupported {
            Toggle("Lock white balance", isOn: Binding(get: { vm.wantLock }, set: { vm.setWhiteBalanceLock($0) }))
            VStack(alignment: .leading) {
                Text("Locked at \(Int(vm.wbKelvin))K")
                Slider(value: Binding(get: { vm.wbKelvin }, set: { vm.setWhiteBalanceKelvin($0) }), in: 2500...8000, step: 100)
            }
            Text(vm.lockedKelvin != nil
                 ? "Locked. Light of \(Int(vm.wbKelvin))K looks neutral to the camera, and readings are corrected for that. Set it near the light you expect."
                 : "Automatic" + (vm.autoKelvin.map { ". The camera's own guess right now: \(Int(($0 / 50).rounded() * 50))K." } ?? "."))
                .font(.footnote).foregroundColor(Theme.muted)
        } else {
            Text("This camera can't lock white balance.").foregroundColor(Theme.muted)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Measuring mode") {
                    Picker("Mode", selection: Binding(get: { vm.cardMode }, set: { vm.setCardMode($0) })) {
                        Text("Card (easy)").tag(true)
                        Text("Manual lock").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(vm.cardMode
                         ? "Hold a white or gray card in the square. The app adjusts the camera's white balance until the card looks neutral, then reads the colour temperature from Apple's own factory calibration of your camera. No lock or calibration needed to start."
                         : "Advanced. You lock the camera's white balance yourself and calibrate against lights of known colour.")
                        .font(.footnote).foregroundColor(Theme.muted)
                }

                if !vm.cardMode {
                    Section("White balance") {
                        whiteBalanceControls
                    }
                }

                Section("Exposure") {
                    Toggle("Lock exposure", isOn: Binding(get: { vm.exposureLockWanted }, set: { vm.setExposureLock($0) }))
                    Text(vm.exposureLockWanted
                         ? "Exposure is frozen. If the card looks too dark or too bright, turn this off."
                         : "Automatic: exposure follows the white square, so the card is exposed well whatever is around it. It also freezes during a Measure.")
                        .font(.footnote).foregroundColor(Theme.muted)
                }

                Section("Measure area") {
                    Picker("Size", selection: $vm.areaFraction) {
                        Text("10%").tag(0.1); Text("20%").tag(0.2); Text("35%").tag(0.35); Text("50%").tag(0.5)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Calibrate (optional)") {
                    Text(vm.cardMode
                         ? "Optional. Card mode already uses Apple's calibration, so try it as is. If a light you know the colour of reads off, point at it with the card, tap Measure, type its Kelvin below and add it. The correction then applies to every reading."
                         : "Point at a light of known Kelvin (a bulb's label, a panel, a real meter), tap Measure, type its Kelvin below and add it. Use two lights, one warm (like 2700K) and one cool (like 5600K), for the best consistency.")
                        .font(.footnote).foregroundColor(Theme.muted)
                    // live check: is the calibration actually changing the number?
                    if let raw = vm.uncalibratedKelvin, let shown = vm.reading?.kelvin {
                        HStack { Text("Camera reads"); Spacer(); Text("\(Int((raw / 10).rounded() * 10))K").monospacedDigit() }
                        HStack { Text("Shown after calibration"); Spacer(); Text("\(Int((shown / 10).rounded() * 10))K").monospacedDigit() }
                    }
                    Text(fitDescription).font(.footnote).foregroundColor(Theme.muted)
                    TextField("Known Kelvin, e.g. 5600", text: $knownKelvin).keyboardType(.numberPad)
                    Button("Add calibration point") {
                        if let k = Double(knownKelvin), vm.addCalibrationPoint(knownKelvin: k) {
                            knownKelvin = ""
                            message = nil
                        } else {
                            message = "Point the camera at the light and enter its Kelvin (above 1000) first."
                        }
                    }
                    ForEach(vm.calPoints.indices, id: \.self) { i in
                        Text("Truth \(Int((1e6 / vm.calPoints[i].t).rounded()))K · camera said \(Int((1e6 / vm.calPoints[i].m).rounded()))K")
                    }
                    .onDelete { vm.calPoints.remove(atOffsets: $0) }
                    if !vm.calPoints.isEmpty {
                        Button("Reset calibration", role: .destructive) { vm.resetCalibration() }
                    }
                    if let message = message { Text(message).font(.footnote).foregroundColor(Theme.warm) }
                }

                Section("Reference") {
                    Text(vm.referenceKelvin.map { "Comparing against \($0)K" } ?? "No reference set. Use the circle button to lock in the current look.")
                        .font(.footnote).foregroundColor(Theme.muted)
                    if vm.referenceKelvin != nil { Button("Clear reference") { vm.referenceKelvin = nil } }
                }

                Section("Save this reading") {
                    TextField("Note (e.g. Sanctuary stage, 10am)", text: $note)
                    Button("Save to library") {
                        if let shot = vm.makeShot(note: note) {
                            library.add(shot)
                            note = ""
                            dismiss()
                        } else {
                            message = "Nothing to save yet. Start the camera and point at something."
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
