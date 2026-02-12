import XCTest
@testable import TrainCam

final class CameraModelTests: XCTestCase {

    // MARK: - Initialization

    func testESP32CameraInit() {
        let cam = Camera(id: "192.168.1.10", name: "traincam-esp1", host: "traincam-esp1.local",
                         ip: "192.168.1.10", port: 80, source: .mdns, cameraType: .esp32)
        XCTAssertEqual(cam.id, "192.168.1.10")
        XCTAssertEqual(cam.name, "traincam-esp1")
        XCTAssertEqual(cam.host, "traincam-esp1.local")
        XCTAssertEqual(cam.port, 80)
        XCTAssertEqual(cam.source, .mdns)
        XCTAssertEqual(cam.cameraType, .esp32)
    }

    func testPiCameraInit() {
        let cam = Camera(id: "192.168.1.20", name: "traincam1", host: "traincam1.local",
                         ip: "192.168.1.20", port: 8080, source: .manual, cameraType: .pi)
        XCTAssertEqual(cam.cameraType, .pi)
        XCTAssertEqual(cam.source, .manual)
    }

    // MARK: - Camera Type Detection

    func testIsPi() {
        let pi = Camera(id: "1", name: "pi", host: "pi.local", ip: "10.0.0.1", port: 8080, source: .mdns, cameraType: .pi)
        let esp = Camera(id: "2", name: "esp", host: "esp.local", ip: "10.0.0.2", port: 80, source: .mdns, cameraType: .esp32)
        XCTAssertTrue(pi.isPi)
        XCTAssertFalse(esp.isPi)
    }

    // MARK: - Base URL

    func testBaseURLPort80() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 80, source: .mdns, cameraType: .esp32)
        XCTAssertEqual(cam.baseURL, "http://10.0.0.1")
    }

    func testBaseURLNonStandardPort() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 8080, source: .mdns, cameraType: .pi)
        XCTAssertEqual(cam.baseURL, "http://10.0.0.1:8080")
    }

    // MARK: - ESP32 URLs

    func testESP32StreamURL() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 80, source: .mdns, cameraType: .esp32)
        XCTAssertEqual(cam.streamURL?.absoluteString, "http://10.0.0.1/stream")
    }

    func testESP32TelemetryURL() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 80, source: .mdns, cameraType: .esp32)
        XCTAssertEqual(cam.telemetryURL?.absoluteString, "http://10.0.0.1/telemetry")
    }

    func testESP32ViewerURLIsNil() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 80, source: .mdns, cameraType: .esp32)
        XCTAssertNil(cam.viewerURL)
        XCTAssertNil(cam.playerURL)
    }

    // MARK: - Pi URLs

    func testPiViewerURL() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 8080, source: .mdns, cameraType: .pi)
        XCTAssertEqual(cam.viewerURL?.absoluteString, "http://10.0.0.1:8080/viewer.html")
    }

    func testPiPlayerURL() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 8080, source: .mdns, cameraType: .pi)
        XCTAssertEqual(cam.playerURL?.absoluteString, "http://10.0.0.1:8080/player")
    }

    func testPiStreamURLIsNil() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 8080, source: .mdns, cameraType: .pi)
        XCTAssertNil(cam.streamURL)
        XCTAssertNil(cam.telemetryURL)
    }

    // MARK: - Status URL (both types)

    func testStatusURLAvailableForBothTypes() {
        let esp = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 80, source: .mdns, cameraType: .esp32)
        let pi = Camera(id: "2", name: "c", host: "c.local", ip: "10.0.0.2", port: 8080, source: .mdns, cameraType: .pi)
        XCTAssertEqual(esp.statusURL?.absoluteString, "http://10.0.0.1/status")
        XCTAssertEqual(pi.statusURL?.absoluteString, "http://10.0.0.2:8080/status")
    }

    // MARK: - Identity

    func testCameraIdentity() {
        let cam1 = Camera(id: "192.168.1.10", name: "a", host: "a.local", ip: "192.168.1.10", port: 80, source: .mdns, cameraType: .esp32)
        let cam2 = Camera(id: "192.168.1.10", name: "b", host: "b.local", ip: "192.168.1.10", port: 80, source: .ble, cameraType: .esp32)
        XCTAssertEqual(cam1.id, cam2.id)
    }

    func testCameraHashable() {
        let cam = Camera(id: "1", name: "c", host: "c.local", ip: "10.0.0.1", port: 80, source: .mdns, cameraType: .esp32)
        var set = Set<Camera>()
        set.insert(cam)
        set.insert(cam)
        XCTAssertEqual(set.count, 1)
    }
}
