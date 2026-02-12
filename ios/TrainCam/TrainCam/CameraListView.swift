import SwiftUI

/// Main screen: shows all discovered cameras in a scrollable list.
struct CameraListView: View {
    @EnvironmentObject var discovery: CameraDiscovery
    @State private var showManualAdd = false
    @State private var showSettings = false
    @State private var manualIP = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if discovery.cameras.isEmpty {
                            if discovery.scanTimedOut {
                                // Empty state after timeout
                                VStack(spacing: 16) {
                                    Image(systemName: "video.slash")
                                        .font(.system(size: 48))
                                        .foregroundColor(.gray)
                                    Text("No Cameras Found")
                                        .font(.title3.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text("Make sure your TrainCam devices are powered on and connected to the same Wi-Fi network.")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)

                                    VStack(spacing: 10) {
                                        Button {
                                            discovery.refresh()
                                        } label: {
                                            Label("Scan Again", systemImage: "arrow.clockwise")
                                                .font(.system(size: 15, weight: .medium))
                                                .frame(maxWidth: 200)
                                                .padding(.vertical, 10)
                                                .background(Color.appAccent)
                                                .foregroundColor(.white)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .accessibilityLabel("Scan again for cameras")

                                        Button {
                                            showManualAdd = true
                                        } label: {
                                            Label("Add by IP Address", systemImage: "plus")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.gray)
                                        }
                                        .accessibilityLabel("Add camera by IP address")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("No cameras found. Scan again or add a camera by IP address.")
                            } else {
                                // Scanning in progress
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                        .tint(.cyan)
                                    Text("Scanning for cameras...")
                                        .foregroundColor(.gray)
                                    Text("Looking for _traincam._tcp on your network")
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Scanning for cameras on the network")
                            }
                        }

                        ForEach(discovery.cameras) { camera in
                            NavigationLink(destination: CameraDetailView(camera: camera)) {
                                CameraCardView(camera: camera)
                            }
                            .buttonStyle(.plain)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .accessibilityLabel("Camera: \(camera.name) at \(camera.ip)")
                            .accessibilityHint("Double tap to view live stream")
                            .contextMenu {
                                if camera.source == .manual {
                                    Button(role: .destructive) {
                                        discovery.removeManualCamera(camera)
                                    } label: {
                                        Label("Remove Saved Camera", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .animation(.easeInOut(duration: 0.3), value: discovery.cameras.count)
                }
            }
            .navigationTitle("Cameras")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            discovery.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button {
                            showManualAdd = true
                        } label: {
                            Label("Add Camera by IP", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Camera options")
                }
            }
            .alert("Add Camera", isPresented: $showManualAdd) {
                TextField("IP Address", text: $manualIP)
                    .keyboardType(.decimalPad)
                Button("Add") {
                    if !manualIP.isEmpty {
                        discovery.addManual(ip: manualIP)
                        manualIP = ""
                    }
                }
                Button("Cancel", role: .cancel) { manualIP = "" }
            } message: {
                Text("Enter the camera's IP address")
            }
            .refreshable {
                await discovery.refreshAsync()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showSettings = false }
                                    .foregroundColor(.cyan)
                            }
                        }
                }
            }
        }
    }
}

/// About sheet with app info and external links.
struct AboutView: View {
    let openURL: OpenURLAction
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "train.side.front.car")
                        .font(.system(size: 48))
                        .foregroundColor(.appAccent)
                    Text("RailCam")
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)
                    Text("Version \(appVersion)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("Live camera streaming for model railroads.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    VStack(spacing: 12) {
                        Button {
                            openURL(AppURL.privacyPolicy)
                        } label: {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                                .frame(maxWidth: 220)
                                .padding(.vertical, 10)
                                .background(Color(white: 0.15))
                                .foregroundColor(.appAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .accessibilityLabel("Open privacy policy in Safari")

                        Button {
                            openURL(AppURL.sourceCode)
                        } label: {
                            Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                                .frame(maxWidth: 220)
                                .padding(.vertical, 10)
                                .background(Color(white: 0.15))
                                .foregroundColor(.appAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .accessibilityLabel("Open source code on GitHub")
                    }
                    .padding(.top, 10)

                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.appAccent)
                }
            }
        }
    }
}

/// Card in the camera list -- shows status info (NO live stream to save bandwidth).
/// Tap to go to detail view for live stream.
struct CameraCardView: View {
    let camera: Camera
    @StateObject private var fetcher = TelemetryFetcher()
    @AppStorage("tempUnit") private var tempUnit: String = "celsius"

    private var useFahrenheit: Bool { tempUnit == "fahrenheit" }

    var body: some View {
        VStack(spacing: 0) {
            // Placeholder with subtle gradient
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.08), Color(white: 0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 8) {
                    Image(systemName: camera.isPi ? "desktopcomputer" : "video.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.cyan.opacity(0.5))
                    Text(camera.isPi ? "Tap to view WebRTC stream" : "Tap to view live stream")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
            .frame(height: 160)
            .accessibilityHidden(true)

            // Info bar
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(fetcher.telemetry != nil ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel(fetcher.telemetry != nil ? "Online" : "Connecting")
                        Text(camera.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(camera.ip)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }

                Spacer()

                if let t = fetcher.telemetry {
                    HStack(spacing: 10) {
                        if let rssi = t.rssi {
                            Label("\(rssi)", systemImage: "wifi")
                                .font(.system(size: 10))
                                .foregroundColor(rssi > -50 ? .green : rssi > -70 ? .orange : .red)
                                .accessibilityLabel("Wi-Fi signal \(rssi) dBm")
                        }
                        Label(String(format: "%.0f\u{00B0}%@", useFahrenheit ? t.temperature_f : t.temperature_c, useFahrenheit ? "F" : "C"), systemImage: "thermometer.medium")
                            .font(.system(size: 10))
                            .foregroundColor(t.temperature_c < 55 ? .white : .red)
                            .accessibilityLabel("Temperature \(String(format: "%.0f", useFahrenheit ? t.temperature_f : t.temperature_c)) degrees \(useFahrenheit ? "Fahrenheit" : "Celsius")")
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.gray)
                        .accessibilityLabel("Loading status")
                }

                HStack(spacing: 8) {
                    Image(systemName: camera.source == .ble ? "antenna.radiowaves.left.and.right" : camera.source == .manual ? "hand.raised.fill" : "bonjour")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.5))
                        .accessibilityLabel("Discovered via \(camera.source.rawValue)")

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.3))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.cardBackground)
        }
        .background(Color.sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .onAppear { fetcher.start(camera: camera) }
        .onDisappear { fetcher.stop() }
    }
}
