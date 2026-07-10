import Foundation
import XCTest
@testable import NotchShelf

final class CaptureArrivalTimingTests: XCTestCase {
    func testFlightAndSourceHaloStartWithoutAStationaryLeadIn() {
        XCTAssertEqual(CaptureArrivalTiming.movementStartDelay, 0)
        XCTAssertEqual(CaptureArrivalTiming.sourceHaloStartDelay, 0)
    }

    func testReducedMotionStillStartsImmediately() {
        XCTAssertEqual(CaptureArrivalTiming.reducedMotionStartDelay, 0)
        XCTAssertEqual(CaptureArrivalTiming.reducedMotionDuration, 0.28)
    }

    func testImmediateHandoffPreservesReadableFlightTiming() {
        XCTAssertEqual(CaptureArrivalTiming.sourceHaloDuration, 0.19)
        XCTAssertEqual(CaptureArrivalTiming.positionDuration, 0.48)
        XCTAssertEqual(CaptureArrivalTiming.flightDuration, 0.64)
        XCTAssertLessThan(
            CaptureArrivalTiming.positionDuration,
            CaptureArrivalTiming.flightDuration,
            "The remaining tail lets the thumbnail fade at the notch before the final pulse"
        )
    }
}
