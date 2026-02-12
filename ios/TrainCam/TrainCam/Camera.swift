import Foundation

/// Represents a discovered TrainCam camera on the network.
struct Camera: Identifiable, Hashable, Sendable, Codable {
    let id: String          // IP address or unique key
    let name: String        // e.g. "traincam-esp1"
    let host: String        // e.g. "traincam-esp1.local"
    let ip: String
    let port: Int
    var source: DiscoverySource
    var cameraType: CameraType

    enum DiscoverySource: String, Hashable, Sendable, Codable {
        case mdns, ble, manual
    }

    enum CameraType: String, Hashable, Sendable, Codable {
        case esp32
        case pi
    }

    var isPi: Bool { cameraType == .pi }

    var baseURL: String {
        port == 80 ? "http://\(ip)" : "http://\(ip):\(port)"
    }

    /// MJPEG stream URL (ESP32 only).
    var streamURL: URL? {
        guard !isPi else { return nil }
        return URL(string: "\(baseURL)/stream")
    }

    /// WebRTC viewer page (Pi only).
    var viewerURL: URL? {
        guard isPi else { return nil }
        return URL(string: "\(baseURL)/viewer.html")
    }

    /// Minimal WebRTC player page for embedding (Pi only).
    var playerURL: URL? {
        guard isPi else { return nil }
        return URL(string: "\(baseURL)/player")
    }

    var statusURL: URL? {
        URL(string: "\(baseURL)/status")
    }

    var telemetryURL: URL? {
        guard !isPi else { return nil }
        return URL(string: "\(baseURL)/telemetry")
    }
}

/// Telemetry data from a camera's /status endpoint.
/// Fields are optional where ESP32 and Pi return different data.
struct CameraTelemetry: Codable, Hashable, Sendable {
    let hostname: String
    let uptime_s: Int
    let rssi: Int?
    let free_heap: Int?
    let psram_free: Int?
    let temperature_c: Double
    let temperature_f: Double
    let wifi: String?
    let ip: String
    let mac: String?
    let type: String?
    let free_mem: Int?
    let stream: String?
}
