import Foundation
import SwiftUI

struct Shot: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var kelvin: Int
    var tint: Double
    var brightness: Int          // percent
    var rgb: [Int]               // 0-255
    var note: String
}

/// Saved readings, kept on the phone.
final class ShotStore: ObservableObject {
    @Published private(set) var shots: [Shot] = []
    private static let key = "ts_shots_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Shot].self, from: data) {
            shots = saved
        }
    }

    func add(_ shot: Shot) {
        shots.insert(shot, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        shots.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        shots = []
        save()
    }

    var exportText: String {
        shots.map { s in
            let when = s.date.formatted(date: .abbreviated, time: .shortened)
            return "\(when) | \(s.kelvin)K | tint \(String(format: "%.1f", s.tint)) | \(s.brightness)% | \(s.note)"
        }.joined(separator: "\n")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shots) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
