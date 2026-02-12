import SwiftUI

/// Settings screen with stream, display, and about sections.
struct SettingsView: View {
    @AppStorage("connectionTimeout") private var connectionTimeout: Int = 10
    @AppStorage("autoReconnect") private var autoReconnect: Bool = true
    @AppStorage("tempUnit") private var tempUnit: String = "celsius"
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Form {
            // MARK: - Stream
            Section("Stream") {
                Picker("Connection Timeout", selection: $connectionTimeout) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                }
                .accessibilityLabel("Connection timeout")

                Toggle("Auto-Reconnect", isOn: $autoReconnect)
                    .accessibilityLabel("Auto-reconnect on stream failure")
            }

            // MARK: - Display
            Section("Display") {
                Picker("Temperature Unit", selection: $tempUnit) {
                    Text("Celsius").tag("celsius")
                    Text("Fahrenheit").tag("fahrenheit")
                }
                .accessibilityLabel("Temperature unit")
            }

            // MARK: - About
            Section("About") {
                HStack(spacing: 12) {
                    Image(systemName: "train.side.front.car")
                        .font(.system(size: 28))
                        .foregroundColor(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RailCam")
                            .font(.headline)
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("RailCam version \(appVersion)")

                Button {
                    openURL(URL(string: "https://djdefi.github.io/traincam-ncngrr/privacy-policy.html")!)
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
                .accessibilityLabel("Open privacy policy in Safari")

                Button {
                    openURL(URL(string: "https://github.com/djdefi/traincam-ncngrr")!)
                } label: {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .accessibilityLabel("Open source code on GitHub")

                Button {
                    // Placeholder — replace with actual App Store URL when available
                    if let url = URL(string: "https://apps.apple.com/app/id0000000000") {
                        openURL(url)
                    }
                } label: {
                    Label("Rate on App Store", systemImage: "star.fill")
                }
                .accessibilityLabel("Rate RailCam on the App Store")
            }
        }
        .navigationTitle("Settings")
        .tint(.cyan)
    }
}
