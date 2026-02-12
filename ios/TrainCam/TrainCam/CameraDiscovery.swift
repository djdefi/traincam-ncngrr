import Foundation
import Network
import Combine
import CoreBluetooth
import UIKit

/// Discovers TrainCam cameras via mDNS (Bonjour) and BLE.
@MainActor
final class CameraDiscovery: NSObject, ObservableObject {
    @Published var cameras: [Camera] = []
    @Published var isScanning = false
    @Published var scanTimedOut = false
    @Published var isDetectingType = false

    private var browser: NWBrowser?
    private var resolvedCameras: [String: Camera] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var bleScanTask: Task<Void, Never>?

    // BLE
    private var centralManager: CBCentralManager?
    private var bleCameras: [String: Camera] = [:]

    // Haptic
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private static let manualCamerasKey = "manualCameras"

    override init() {
        super.init()
        haptic.prepare()
        loadManualCameras()
        startMDNS()
        startBLE()
        startScanTimeout()
    }

    // MARK: - Scan Timeout

    private func startScanTimeout() {
        timeoutTask?.cancel()
        scanTimedOut = false
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if self.cameras.isEmpty {
                self.scanTimedOut = true
                self.isScanning = false
            }
        }
    }

    // MARK: - mDNS Discovery

    func startMDNS() {
        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_traincam._tcp", domain: "local."), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleBrowseResults(results)
            }
        }
        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[mDNS] Browsing for _traincam._tcp")
            case .failed(let error):
                print("[mDNS] Browse failed: \(error)")
            default:
                break
            }
        }
        browser?.start(queue: .main)
        isScanning = true
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            // Extract TXT record metadata to determine camera type
            var txtDict: [String: String] = [:]
            if case .bonjour(let record) = result.metadata {
                for key in record.dictionary.keys {
                    if let value = record.dictionary[key] {
                        txtDict[key] = value
                    }
                }
            }
            resolveEndpoint(result.endpoint, txtRecords: txtDict)
        }
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint, txtRecords: [String: String] = [:]) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   let remoteEndpoint = path.remoteEndpoint,
                   case .hostPort(let host, let port) = remoteEndpoint {
                    let ip = "\(host)"
                        .replacingOccurrences(of: "%.*", with: "", options: .regularExpression)
                    let portNum = Int(port.rawValue)
                    let name: String
                    if case .service(let n, _, _, _) = endpoint {
                        name = n
                    } else {
                        name = ip
                    }

                    // Determine camera type from TXT records
                    let camType: Camera.CameraType = txtRecords["type"] == "pi" ? .pi : .esp32

                    let cam = Camera(
                        id: ip,
                        name: name,
                        host: "\(name).local",
                        ip: ip,
                        port: portNum,
                        source: .mdns,
                        cameraType: camType
                    )
                    Task { @MainActor [weak self] in
                        self?.addCamera(cam)
                    }
                }
                connection.cancel()
            case .failed:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))

        // Timeout: cancel if not resolved within 5 seconds
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
    }

    // MARK: - BLE Discovery

    func startBLE() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        // Stop BLE scanning after 15 seconds to save battery
        bleScanTask?.cancel()
        bleScanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.centralManager?.stopScan()
            print("[BLE] Scan stopped (15s timeout)")
        }
    }

    // MARK: - Camera Management

    private func addCamera(_ camera: Camera) {
        if resolvedCameras[camera.id] == nil {
            resolvedCameras[camera.id] = camera
            haptic.impactOccurred()
            rebuildList()
        }
    }

    private func rebuildList() {
        var merged = resolvedCameras
        for (k, v) in bleCameras {
            if merged[k] == nil {
                merged[k] = v
            }
        }
        cameras = Array(merged.values).sorted { $0.name < $1.name }
        if !cameras.isEmpty {
            scanTimedOut = false
        }
    }

    func addManual(ip: String, port: Int = 80, cameraType: Camera.CameraType = .esp32) {
        let cam = Camera(id: ip, name: ip, host: ip, ip: ip, port: port, source: .manual, cameraType: cameraType)
        resolvedCameras[ip] = cam
        saveManualCameras()
        rebuildList()
    }

    /// Add a camera by IP, auto-detecting its type first.
    func addManualWithDetection(ip: String, port: Int = 80) async {
        isDetectingType = true
        let detected = await detectCameraType(host: ip, port: port)
        isDetectingType = false
        addManual(ip: ip, port: port, cameraType: detected)
    }

    /// Probes a host to determine if it's an ESP32 or Pi camera.
    func detectCameraType(host: String, port: Int) async -> Camera.CameraType {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let probeSession = URLSession(configuration: config)
        defer { probeSession.invalidateAndCancel() }

        // Probe 1: GET /status — returns JSON with "type" field
        if let statusURL = URL(string: "http://\(host):\(port)/status") {
            do {
                let (data, _) = try await probeSession.data(from: statusURL)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String {
                    if type == "pi" { return .pi }
                    if type == "esp32" { return .esp32 }
                }
            } catch {
                // Continue to next probe
            }
        }

        // Probe 2: GET http://{host}:8889/ — Pi with MediaMTX WebRTC
        if let whepURL = URL(string: "http://\(host):8889/") {
            do {
                let (_, response) = try await probeSession.data(from: whepURL)
                if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                    return .pi
                }
            } catch {
                // Continue to fallback
            }
        }

        return .esp32
    }

    func removeManualCamera(_ camera: Camera) {
        guard camera.source == .manual else { return }
        resolvedCameras.removeValue(forKey: camera.id)
        saveManualCameras()
        rebuildList()
    }

    func refresh() {
        browser?.cancel()
        // Preserve manual cameras across refresh
        let manuals = resolvedCameras.filter { $0.value.source == .manual }
        resolvedCameras = manuals
        bleCameras.removeAll()
        cameras.removeAll()
        haptic.prepare()
        startMDNS()
        startBLE()
        startScanTimeout()
        rebuildList()
    }

    /// Async refresh for pull-to-refresh. Rescans and waits up to 3 seconds
    /// to give mDNS a chance to find cameras before returning.
    func refreshAsync() async {
        refresh()
        // Give mDNS time to discover cameras (up to 3 seconds)
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(500))
            if !cameras.isEmpty { break }
        }
    }

    // MARK: - Manual Camera Persistence

    private func saveManualCameras() {
        let manuals = resolvedCameras.values.filter { $0.source == .manual }
        if let data = try? JSONEncoder().encode(Array(manuals)) {
            UserDefaults.standard.set(data, forKey: Self.manualCamerasKey)
        }
    }

    private func loadManualCameras() {
        guard let data = UserDefaults.standard.data(forKey: Self.manualCamerasKey),
              let saved = try? JSONDecoder().decode([Camera].self, from: data) else { return }
        for camera in saved {
            resolvedCameras[camera.id] = camera
        }
        rebuildList()
    }

}

// MARK: - CBCentralManagerDelegate

extension CameraDiscovery: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Scan for Environmental Sensing service (0x181A)
            central.scanForPeripherals(
                withServices: [CBUUID(string: "181A")],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            print("[BLE] Scanning for TrainCam beacons (0x181A)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              name.contains("traincam") else { return }
        print("[BLE] Found: \(name) RSSI=\(RSSI)")
        // BLE gives us the name; we still need to resolve the IP via mDNS or connect to GATT
        // For now, add a placeholder that mDNS will fill with the real IP
    }
}
