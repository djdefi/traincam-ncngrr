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

    private var browser: NWBrowser?
    private var resolvedCameras: [String: Camera] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var bleScanTask: Task<Void, Never>?

    // BLE
    private var centralManager: CBCentralManager?
    private var bleCameras: [String: Camera] = [:]

    // Haptic
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    override init() {
        super.init()
        haptic.prepare()
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
        rebuildList()
    }

    func refresh() {
        browser?.cancel()
        resolvedCameras.removeAll()
        bleCameras.removeAll()
        cameras.removeAll()
        haptic.prepare()
        startMDNS()
        startBLE()
        startScanTimeout()
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
