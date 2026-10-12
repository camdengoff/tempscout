import Foundation
import TempScoutCore

/// The two exposures on the ND tab (what looks right now, and what you want instead). Shared with the Meter panel.
final class NDModel: ObservableObject {
    @Published var base: Exposure { didSet { save() } }
    @Published var wanted: Exposure { didSet { save() } }

    private struct Saved: Codable {
        var base: Exposure
        var wanted: Exposure
    }
    private static let key = "ts_nd_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            base = saved.base
            wanted = saved.wanted
        } else {
            base = Exposure(aperture: 11, shutter: 1.0 / 48, iso: 100)
            wanted = Exposure(aperture: 2.8, shutter: 1.0 / 48, iso: 100)
        }
    }

    var result: NDCalculator.Result { NDCalculator.compute(base: base, wanted: wanted) }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(base: base, wanted: wanted)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
