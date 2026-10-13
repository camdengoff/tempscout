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
    @StateObject private var library = ShotStore()
    @StateObject private var app = AppState()
    // Plain references, not observed here: the ND page reads them through the environment (see CameraEnvironment.swift)
    private let camera: CameraController
    private let live: FrameLiveModel

    init() {
        // the Meter and the ND page share one camera
        let camera = CameraController()
        let plan = FramePlanModel()
        self.camera = camera
        self.live = FrameLiveModel(camera: camera, plan: plan)
        _meter = StateObject(wrappedValue: MeterViewModel(camera: camera))
        _plan = StateObject(wrappedValue: plan)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(meter)
                .environmentObject(plan)
                .environment(\.frameCamera, camera)
                .environment(\.frameLive, live)
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
