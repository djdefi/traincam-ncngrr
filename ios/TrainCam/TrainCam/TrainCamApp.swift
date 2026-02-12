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
                .tint(.appAccent)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { if !$0 { hasSeenOnboarding = true } }
                )) {
                    OnboardingView()
                }
        }
    }
}
