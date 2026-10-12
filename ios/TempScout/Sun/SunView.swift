import CoreLocation
import SwiftUI
import TempScoutCore

struct SunView: View {
    @StateObject private var location = LocationProvider()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Use my location") { location.request() }
                    Text(location.message).font(.footnote).foregroundColor(Theme.muted)
                }
                if let c = location.coordinate {
                    Section("Sun times (approximate)") {
                        ForEach(rows(for: c)) { row in
                            HStack {
                                Text(row.title).foregroundColor(Theme.muted)
                                Spacer()
                                Text(row.time).monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    Text("The live sun finder (camera view with the sun's position and path) is coming in the next update.")
                        .font(.footnote).foregroundColor(Theme.muted)
                }
            }
            .navigationTitle("Sun")
        }
    }

    private struct Row: Identifiable {
        let title: String
        let time: String
        var id: String { title }
    }

    private func rows(for c: CLLocationCoordinate2D) -> [Row] {
        let now = Date()
        func time(_ rising: Bool, _ zenith: Double) -> String {
            guard let d = SunMath.event(date: now, latitude: c.latitude, longitude: c.longitude, rising: rising, zenith: zenith) else { return "—" }
            return d.formatted(date: .omitted, time: .shortened)
        }
        return [
            Row(title: "First light", time: time(true, 96)),
            Row(title: "Sunrise", time: time(true, 90.833)),
            Row(title: "Morning golden hour ends", time: time(true, 84)),
            Row(title: "Evening golden hour starts", time: time(false, 84)),
            Row(title: "Sunset", time: time(false, 90.833)),
            Row(title: "Last light", time: time(false, 96))
        ]
    }
}
