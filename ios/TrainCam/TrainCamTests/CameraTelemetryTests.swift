import XCTest
@testable import TrainCam

final class CameraTelemetryTests: XCTestCase {

    // MARK: - Full Payload

    func testDecodeFullPayload() throws {
        let json = """
        {
            "hostname": "traincam-esp1",
            "uptime_s": 3600,
            "rssi": -45,
            "free_heap": 120000,
            "psram_free": 4000000,
            "temperature_c": 42.5,
            "temperature_f": 108.5,
            "wifi": "TrainNet",
            "ip": "192.168.1.10",
            "mac": "AA:BB:CC:DD:EE:FF",
            "type": "esp32",
            "free_mem": 120000,
            "stream": "mjpeg"
        }
        """
        let data = Data(json.utf8)
        let telemetry = try JSONDecoder().decode(CameraTelemetry.self, from: data)

        XCTAssertEqual(telemetry.hostname, "traincam-esp1")
        XCTAssertEqual(telemetry.uptime_s, 3600)
        XCTAssertEqual(telemetry.rssi, -45)
        XCTAssertEqual(telemetry.free_heap, 120000)
        XCTAssertEqual(telemetry.psram_free, 4000000)
        XCTAssertEqual(telemetry.temperature_c, 42.5)
        XCTAssertEqual(telemetry.temperature_f, 108.5)
        XCTAssertEqual(telemetry.wifi, "TrainNet")
        XCTAssertEqual(telemetry.ip, "192.168.1.10")
        XCTAssertEqual(telemetry.mac, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(telemetry.type, "esp32")
        XCTAssertEqual(telemetry.free_mem, 120000)
        XCTAssertEqual(telemetry.stream, "mjpeg")
    }

    // MARK: - Missing Optional Fields

    func testDecodeMinimalPayload() throws {
        let json = """
        {
            "hostname": "traincam1",
            "uptime_s": 600,
            "temperature_c": 55.0,
            "temperature_f": 131.0,
            "ip": "192.168.1.20"
        }
        """
        let data = Data(json.utf8)
        let telemetry = try JSONDecoder().decode(CameraTelemetry.self, from: data)

        XCTAssertEqual(telemetry.hostname, "traincam1")
        XCTAssertEqual(telemetry.uptime_s, 600)
        XCTAssertEqual(telemetry.ip, "192.168.1.20")
        XCTAssertNil(telemetry.rssi)
        XCTAssertNil(telemetry.free_heap)
        XCTAssertNil(telemetry.psram_free)
        XCTAssertNil(telemetry.wifi)
        XCTAssertNil(telemetry.mac)
        XCTAssertNil(telemetry.type)
        XCTAssertNil(telemetry.free_mem)
        XCTAssertNil(telemetry.stream)
    }

    // MARK: - Temperature Values

    func testTemperatureValues() throws {
        let json = """
        {
            "hostname": "test",
            "uptime_s": 0,
            "temperature_c": 25.0,
            "temperature_f": 77.0,
            "ip": "10.0.0.1"
        }
        """
        let data = Data(json.utf8)
        let telemetry = try JSONDecoder().decode(CameraTelemetry.self, from: data)

        XCTAssertEqual(telemetry.temperature_c, 25.0, accuracy: 0.01)
        XCTAssertEqual(telemetry.temperature_f, 77.0, accuracy: 0.01)
    }

    func testHighTemperature() throws {
        let json = """
        {
            "hostname": "hot-cam",
            "uptime_s": 86400,
            "temperature_c": 85.0,
            "temperature_f": 185.0,
            "ip": "10.0.0.1"
        }
        """
        let data = Data(json.utf8)
        let telemetry = try JSONDecoder().decode(CameraTelemetry.self, from: data)

        XCTAssertEqual(telemetry.temperature_c, 85.0, accuracy: 0.01)
        XCTAssertEqual(telemetry.temperature_f, 185.0, accuracy: 0.01)
    }

    // MARK: - Invalid JSON

    func testDecodeMissingRequiredField() {
        let json = """
        {
            "hostname": "test",
            "ip": "10.0.0.1"
        }
        """
        let data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CameraTelemetry.self, from: data))
    }
}
