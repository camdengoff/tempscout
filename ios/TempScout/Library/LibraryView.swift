import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: ShotStore
    @EnvironmentObject var meter: MeterViewModel
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if library.shots.isEmpty {
                    Text("No saved readings yet.")
                        .foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(library.shots) { shot in
                            row(shot)
                        }
                        .onDelete { library.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                if !library.shots.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        ShareLink(item: library.exportText) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Delete all", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Delete all saved readings?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { library.clear() }
            }
        }
    }

    private func row(_ shot: Shot) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: Double(shot.rgb[0]) / 255, green: Double(shot.rgb[1]) / 255, blue: Double(shot.rgb[2]) / 255))
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(shot.kelvin)K").font(.headline)
                    Text("tint \(String(format: "%.1f", shot.tint)) · \(shot.brightness)%")
                        .font(.footnote).foregroundColor(Theme.muted)
                }
                if !shot.note.isEmpty { Text(shot.note).font(.subheadline) }
                Text(shot.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundColor(Theme.muted)
            }
            Spacer()
            Button("Use as ref") { meter.referenceKelvin = shot.kelvin }
                .font(.footnote)
                .buttonStyle(.bordered)
        }
    }
}
