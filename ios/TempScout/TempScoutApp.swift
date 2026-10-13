import SwiftUI

enum AppTab: Hashable {
    case meter, nd, library, sun
}

final class AppState: ObservableObject {
    @Published var tab: AppTab = .meter
}

@main
struct TempScoutApp: App {
    @StateObject private var meter: MeterViewModel
    @StateObject private var plan: FramePlanModel
    @StateObject private var live: FrameLiveModel
    @StateObject private var library = ShotStore()
    @StateObject private var app = AppState()

    init() {
        // the Meter and the ND page share one camera
        let camera = CameraController()
        let plan = FramePlanModel()
        _meter = StateObject(wrappedValue: MeterViewModel(camera: camera))
        _plan = StateObject(wrappedValue: plan)
        _live = StateObject(wrappedValue: FrameLiveModel(camera: camera, plan: plan))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(meter)
                .environmentObject(plan)
                .environmentObject(live)
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
            FrameView()
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
