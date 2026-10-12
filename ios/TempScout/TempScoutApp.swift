import SwiftUI

enum AppTab: Hashable {
    case meter, nd, library, sun
}

final class AppState: ObservableObject {
    @Published var tab: AppTab = .meter
}

@main
struct TempScoutApp: App {
    @StateObject private var meter = MeterViewModel()
    @StateObject private var nd = NDModel()
    @StateObject private var library = ShotStore()
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(meter)
                .environmentObject(nd)
                .environmentObject(library)
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView(selection: $app.tab) {
            MeterView()
                .tabItem { Label("Meter", systemImage: "camera.metering.center.weighted") }
                .tag(AppTab.meter)
            NDView()
                .tabItem { Label("ND", systemImage: "circle.lefthalf.filled") }
                .tag(AppTab.nd)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)
            SunView()
                .tabItem { Label("Sun", systemImage: "sun.max") }
                .tag(AppTab.sun)
        }
    }
}
