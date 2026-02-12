import SwiftUI

/// Multi-page onboarding shown on first launch.
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let accentCyan = Color(red: 0.27, green: 0.67, blue: 1.0)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentPage) {
                // Page 1: Welcome
                VStack(spacing: 20) {
                    Spacer()
                    Text("🚂")
                        .font(.system(size: 72))
                    Text("Welcome to RailCam")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.white)
                    Text("View live streams from your model railroad cameras")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                    Spacer()
                }
                .tag(0)

                // Page 2: How it works
                VStack(spacing: 32) {
                    Spacer()
                    Text("How It Works")
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 24) {
                        featureRow(icon: "wifi.circle", text: "Cameras are discovered automatically on your WiFi network")
                        featureRow(icon: "camera.fill", text: "Supports ESP32 and Raspberry Pi cameras")
                        featureRow(icon: "play.circle", text: "Watch live MJPEG and WebRTC streams")
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                    Spacer()
                }
                .tag(1)

                // Page 3: Get started
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 56))
                        .foregroundColor(accentCyan)
                    Text("Ready to Go")
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)
                    Text("Make sure your camera is powered on and connected to WiFi")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button {
                        hasSeenOnboarding = true
                        dismiss()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: 240)
                            .padding(.vertical, 14)
                            .background(accentCyan)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 12)

                    Spacer()
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(accentCyan)
                .frame(width: 36)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }
}
