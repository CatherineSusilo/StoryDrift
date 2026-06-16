import XCTest
@testable import Idle

final class EyeTrackingManagerTests: XCTestCase {

    func testPERCLOSAlertBand() {
        XCTAssertEqual(EyeTrackingManager.mapPERCLOSToDrift(0.0),  0.0,  accuracy: 0.01)
        XCTAssertLessThan(EyeTrackingManager.mapPERCLOSToDrift(0.04), 25.0)
        XCTAssertEqual(EyeTrackingManager.mapPERCLOSToDrift(0.08), 25.0, accuracy: 0.01)
    }

    func testPERCLOSDrowsyBand() {
        let s = EyeTrackingManager.mapPERCLOSToDrift(0.11)
        XCTAssertGreaterThan(s, 25.0)
        XCTAssertLessThan(s, 60.0)
        XCTAssertEqual(EyeTrackingManager.mapPERCLOSToDrift(0.15), 60.0, accuracy: 0.01)
    }

    func testPERCLOSVeryDrowsyBand() {
        XCTAssertGreaterThanOrEqual(EyeTrackingManager.mapPERCLOSToDrift(0.20), 60.0)
        XCTAssertEqual(EyeTrackingManager.mapPERCLOSToDrift(1.0), 100.0, accuracy: 0.01)
    }

    func testPERCLOSClampsOutOfRange() {
        XCTAssertEqual(EyeTrackingManager.mapPERCLOSToDrift(-0.5), 0.0, accuracy: 0.01)
        XCTAssertEqual(EyeTrackingManager.mapPERCLOSToDrift( 1.5), 100.0, accuracy: 0.01)
    }
}
