import SwiftUI
import TempScoutCore

struct NDView: View {
    @EnvironmentObject var nd: NDModel

    var body: some View {
        NavigationStack {
            Form {
                Section("1 · Exposure that looks right now (no ND)") {
                    exposurePickers($nd.base)
                }
                Section("2 · Settings you want instead") {
                    exposurePickers($nd.wanted)
                }
                Section {
                    resultCard
                }
                Section {
                    Text("Example: you're outside at f/11, 1/48, ISO 100 and want a shallow, blurry background at f/2.8. This tells you how strong an ND filter you need to keep the same brightness.")
                        .font(.footnote)
                        .foregroundColor(Theme.muted)
                }
            }
            .navigationTitle("ND")
        }
    }

    @ViewBuilder
    private func exposurePickers(_ e: Binding<Exposure>) -> some View {
        Picker("Aperture", selection: e.aperture) {
            ForEach(NDCalculator.apertures, id: \.self) { Text(NDCalculator.apertureLabel($0)).tag($0) }
        }
        Picker("Shutter", selection: e.shutter) {
            ForEach(NDCalculator.shutters) { Text($0.label).tag($0.seconds) }
        }
        Picker("ISO", selection: e.iso) {
            ForEach(NDCalculator.isos, id: \.self) { Text(NDCalculator.isoLabel($0)).tag($0) }
        }
    }

    private var resultCard: some View {
        let r = nd.result
        return VStack(spacing: 6) {
            Text(r.needed > 0 ? trimmed(r.needed) : "0")
                .font(.system(size: 56, weight: .heavy))
                .foregroundColor(Theme.warm)
            if r.needed > 0 {
                let whole = Int(r.stops.rounded())
                Text("stops of ND needed").font(.headline)
                Text("Closest filter: ND\(Int(pow(2.0, Double(whole)))) (\(whole) stops, density \(String(format: "%.1f", Double(whole) * 0.3)))")
                    .font(.footnote).foregroundColor(Theme.muted)
                Text("Variable ND: set to about \(trimmed(r.thirdStops)) stops.")
                    .font(.footnote).foregroundColor(Theme.muted)
            } else {
                Text("No ND needed").font(.headline)
                Text(r.thirdStops < -0.15
                     ? "These settings let in \(trimmed(abs(r.thirdStops))) stops LESS light, so you'd be underexposed."
                     : "Both settings give the same exposure.")
                    .font(.footnote).foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func trimmed(_ v: Double) -> String {
        var s = String(format: "%.1f", v)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s
    }
}
