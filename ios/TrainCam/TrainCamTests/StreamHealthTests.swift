import XCTest
@testable import TrainCam

@MainActor
final class StreamHealthTests: XCTestCase {

    // MARK: - Initial State

    func testInitiallyNotStalled() {
        let loader = MJPEGLoader()
        XCTAssertFalse(loader.isStalled)
    }

    func testInitialImageIsNil() {
        let loader = MJPEGLoader()
        XCTAssertNil(loader.image)
    }

    func testInitialErrorMessageIsNil() {
        let loader = MJPEGLoader()
        XCTAssertNil(loader.errorMessage)
    }

    // MARK: - Stall Detection

    func testStartClearsStallFlag() {
        let loader = MJPEGLoader()
        loader.isStalled = true
        let url = URL(string: "http://127.0.0.1:1/stream")!
        loader.start(url: url)
        XCTAssertFalse(loader.isStalled)
        loader.stop()
    }

    func testStartClearsErrorMessage() {
        let loader = MJPEGLoader()
        loader.errorMessage = "Camera unavailable"
        let url = URL(string: "http://127.0.0.1:1/stream")!
        loader.start(url: url)
        XCTAssertNil(loader.errorMessage)
        loader.stop()
    }

    // MARK: - Stop Behavior

    func testStopCanBeCalledSafely() {
        let loader = MJPEGLoader()
        loader.stop()
        XCTAssertFalse(loader.isStalled)
        XCTAssertNil(loader.image)
    }

    func testStopAfterStartDoesNotCrash() {
        let loader = MJPEGLoader()
        let url = URL(string: "http://127.0.0.1:1/stream")!
        loader.start(url: url)
        loader.stop()
        XCTAssertNil(loader.errorMessage)
    }

    // MARK: - Retry Behavior

    func testMultipleStartStopCyclesDoNotCrash() {
        let loader = MJPEGLoader()
        let url = URL(string: "http://127.0.0.1:1/stream")!
        for _ in 0..<5 {
            loader.start(url: url)
            loader.stop()
        }
        XCTAssertFalse(loader.isStalled)
        XCTAssertNil(loader.image)
    }
}
