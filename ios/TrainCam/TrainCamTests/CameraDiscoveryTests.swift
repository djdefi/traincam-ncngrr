import XCTest
@testable import TrainCam

@MainActor
final class CameraDiscoveryTests: XCTestCase {

    private var discovery: CameraDiscovery!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "manualCameras")
        discovery = CameraDiscovery()
    }

    override func tearDown() {
        discovery = nil
        UserDefaults.standard.removeObject(forKey: "manualCameras")
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateHasEmptyCameraList() {
        // mDNS/BLE won't find anything instantly in tests
        // Manual cameras were cleared in setUp
        // Only manually-added cameras would appear synchronously
        let manualOnly = discovery.cameras.filter { $0.source == .manual }
        XCTAssertTrue(manualOnly.isEmpty)
    }

    // MARK: - Add Camera

    func testAddManualAddsToCameraList() {
        discovery.addManual(ip: "192.168.1.50", port: 80, cameraType: .esp32)
        XCTAssertEqual(discovery.cameras.count(where: { $0.source == .manual }), 1)
        XCTAssertEqual(discovery.cameras.first(where: { $0.ip == "192.168.1.50" })?.cameraType, .esp32)
    }

    func testAddManualDuplicateDoesNotCreateDuplicates() {
        discovery.addManual(ip: "10.0.0.1", port: 80, cameraType: .esp32)
        discovery.addManual(ip: "10.0.0.1", port: 80, cameraType: .esp32)
        let matches = discovery.cameras.filter { $0.ip == "10.0.0.1" }
        XCTAssertEqual(matches.count, 1)
    }

    // MARK: - Sorting

    func testCamerasSortedByName() {
        discovery.addManual(ip: "10.0.0.3", port: 80, cameraType: .esp32)  // name = "10.0.0.3"
        discovery.addManual(ip: "10.0.0.1", port: 80, cameraType: .esp32)  // name = "10.0.0.1"
        discovery.addManual(ip: "10.0.0.2", port: 80, cameraType: .esp32)  // name = "10.0.0.2"

        let manualCams = discovery.cameras.filter { $0.source == .manual }
        XCTAssertEqual(manualCams.count, 3)
        XCTAssertEqual(manualCams[0].name, "10.0.0.1")
        XCTAssertEqual(manualCams[1].name, "10.0.0.2")
        XCTAssertEqual(manualCams[2].name, "10.0.0.3")
    }

    // MARK: - Remove Camera

    func testRemoveManualCameraRemovesFromList() {
        discovery.addManual(ip: "192.168.1.99", port: 80, cameraType: .esp32)
        let cam = discovery.cameras.first { $0.ip == "192.168.1.99" }
        XCTAssertNotNil(cam)

        discovery.removeManualCamera(cam!)
        XCTAssertNil(discovery.cameras.first { $0.ip == "192.168.1.99" })
    }
}
