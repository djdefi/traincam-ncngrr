import SwiftUI

@main
struct TrainCamApp: App {
    @StateObject private var discovery = CameraDiscovery()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        WindowGroup {
            CameraListView()
                .environmentObject(discovery)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.27, green: 0.67, blue: 1.0)) // #44AAFF cyan accent
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { if !$0 { hasSeenOnboarding = true } }
                )) {
                    OnboardingView()
                }
        }
    }
}
