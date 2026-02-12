import XCTest
@testable import TrainCam

final class CameraPersistenceTests: XCTestCase {

    // MARK: - Codable Roundtrip

    func testCodableRoundtrip() throws {
        let cam = Camera(id: "192.168.1.10", name: "traincam-esp1", host: "traincam-esp1.local",
                         ip: "192.168.1.10", port: 80, source: .mdns, cameraType: .esp32)
        let data = try JSONEncoder().encode(cam)
        let decoded = try JSONDecoder().decode(Camera.self, from: data)

        XCTAssertEqual(decoded.id, cam.id)
        XCTAssertEqual(decoded.name, cam.name)
        XCTAssertEqual(decoded.host, cam.host)
        XCTAssertEqual(decoded.ip, cam.ip)
        XCTAssertEqual(decoded.port, cam.port)
        XCTAssertEqual(decoded.source, cam.source)
        XCTAssertEqual(decoded.cameraType, cam.cameraType)
    }

    func testEncodeAllFieldsPopulated() throws {
        let cam = Camera(id: "10.0.0.5", name: "traincam1", host: "traincam1.local",
                         ip: "10.0.0.5", port: 8080, source: .manual, cameraType: .pi)
        let data = try JSONEncoder().encode(cam)
        XCTAssertFalse(data.isEmpty)

        let decoded = try JSONDecoder().decode(Camera.self, from: data)
        XCTAssertEqual(decoded.source, .manual)
        XCTAssertEqual(decoded.cameraType, .pi)
        XCTAssertEqual(decoded.port, 8080)
    }

    func testEncodeMinimalFields() throws {
        let cam = Camera(id: "1", name: "", host: "", ip: "1", port: 80, source: .mdns, cameraType: .esp32)
        let data = try JSONEncoder().encode(cam)
        let decoded = try JSONDecoder().decode(Camera.self, from: data)

        XCTAssertEqual(decoded.id, "1")
        XCTAssertEqual(decoded.name, "")
        XCTAssertEqual(decoded.host, "")
    }

    // MARK: - UserDefaults Storage

    func testEncodedDataCanBeStoredInUserDefaults() throws {
        let key = "testCameraPersistence_\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let cam = Camera(id: "192.168.1.10", name: "test-cam", host: "test.local",
                         ip: "192.168.1.10", port: 80, source: .manual, cameraType: .esp32)
        let data = try JSONEncoder().encode([cam])
        UserDefaults.standard.set(data, forKey: key)

        let loaded = UserDefaults.standard.data(forKey: key)
        XCTAssertNotNil(loaded)
        let decoded = try JSONDecoder().decode([Camera].self, from: loaded!)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.id, "192.168.1.10")
    }

    func testLoadingReturnsEmptyWhenNoDataSaved() {
        let key = "testCameraPersistence_nonexistent_\(UUID().uuidString)"
        let data = UserDefaults.standard.data(forKey: key)
        XCTAssertNil(data)
    }

    func testSaveAndLoadMultipleCamerasPreservesOrder() throws {
        let key = "testCameraPersistence_multi_\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let cameras = [
            Camera(id: "1", name: "alpha", host: "a.local", ip: "10.0.0.1", port: 80, source: .manual, cameraType: .esp32),
            Camera(id: "2", name: "bravo", host: "b.local", ip: "10.0.0.2", port: 8080, source: .manual, cameraType: .pi),
            Camera(id: "3", name: "charlie", host: "c.local", ip: "10.0.0.3", port: 80, source: .mdns, cameraType: .esp32),
        ]
        let data = try JSONEncoder().encode(cameras)
        UserDefaults.standard.set(data, forKey: key)

        let loaded = UserDefaults.standard.data(forKey: key)!
        let decoded = try JSONDecoder().decode([Camera].self, from: loaded)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].name, "alpha")
        XCTAssertEqual(decoded[1].name, "bravo")
        XCTAssertEqual(decoded[2].name, "charlie")
    }
}
