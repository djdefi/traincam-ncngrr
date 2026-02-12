import SwiftUI

@main
struct TrainCamApp: App {
    @StateObject private var discovery = CameraDiscovery()

    var body: some Scene {
        WindowGroup {
            CameraListView()
                .environmentObject(discovery)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.27, green: 0.67, blue: 1.0)) // #44AAFF cyan accent
        }
    }
}
