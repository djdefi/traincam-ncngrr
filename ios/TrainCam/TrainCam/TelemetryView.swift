import SwiftUI
import Combine

/// Fetches and displays live telemetry from a camera's /status endpoint.
struct TelemetryView: View {
    let camera: Camera
    @StateObject private var fetcher = TelemetryFetcher()
    @AppStorage("tempUnit") private var tempUnit: String = "celsius"

    private var useFahrenheit: Bool { tempUnit == "fahrenheit" }

    var body: some View {
        VStack(spacing: 0) {
            if let t = fetcher.telemetry {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    if let rssi = t.rssi {
                        TelemetryCard(label: "Signal", value: "\(rssi)", unit: "dBm",
                                      color: rssi > -50 ? .green : rssi > -70 ? .orange : .red)
                    }
                    TelemetryCard(
                        label: "Temp",
                        value: String(format: "%.1f", useFahrenheit ? t.temperature_f : t.temperature_c),
                        unit: useFahrenheit ? "\u{00B0}F" : "\u{00B0}C",
                        color: t.temperature_c < 40 ? .green : t.temperature_c < 55 ? .orange : .red
                    )
                    if let heap = t.free_heap {
                        TelemetryCard(label: "Heap", value: String(format: "%.1f", Double(heap) / 1_048_576), unit: "MB",
                                      color: .cyan)
                    }
                    if let mem = t.free_mem {
                        TelemetryCard(label: "Mem", value: String(format: "%.0f", Double(mem) / 1_048_576), unit: "MB",
                                      color: .cyan)
                    }
                    TelemetryCard(label: "Up", value: formatUptime(t.uptime_s), unit: "",
                                  color: .cyan)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.4), value: t)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Camera telemetry")
            } else if fetcher.telemetryError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Telemetry unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        fetcher.retry()
                    } label: {
                        Text("Retry")
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    .accessibilityLabel("Retry telemetry fetch")
                }
                .padding(12)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Telemetry unavailable")
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(.gray)
                    Text("Loading telemetry...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(12)
                .accessibilityLabel("Loading camera telemetry")
            }
        }
        .onAppear { fetcher.start(camera: camera) }
        .onDisappear { fetcher.stop() }
    }

    private func formatUptime(_ s: Int) -> String {
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }
}

struct TelemetryCard: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.gray)
                .textCase(.uppercase)
                .tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.surfaceBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.04), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }
}

@MainActor
final class TelemetryFetcher: ObservableObject {
    @Published var telemetry: CameraTelemetry?
    @Published var telemetryError: Bool = false
    private var timer: Timer?
    private var camera: Camera?

    func start(camera: Camera) {
        self.camera = camera
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetch()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func retry() {
        telemetryError = false
        fetch()
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }

    private func fetch() {
        guard let url = camera?.statusURL else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                do {
                    let t = try JSONDecoder().decode(CameraTelemetry.self, from: data)
                    self.telemetry = t
                    self.telemetryError = false
                } catch {
                    #if DEBUG
                    print("[Telemetry] Decode error for \(url): \(error)")
                    if let json = String(data: data, encoding: .utf8) {
                        print("[Telemetry] Raw JSON: \(json.prefix(500))")
                    }
                    #endif
                    self.telemetryError = true
                }
            } catch {
                self.telemetryError = true
            }
        }
    }
}
