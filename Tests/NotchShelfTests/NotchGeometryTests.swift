import AppKit
import XCTest
@testable import NotchShelf

final class NotchGeometryTests: XCTestCase {
    func testResolvesPhysicalNotchGapFromAuxiliaryAreas() {
        let screenFrame = CGRect(x: 0, y: 0, width: 2_056, height: 1_329)
        let leftArea = CGRect(x: 0, y: 1_291, width: 918, height: 38)
        let rightArea = CGRect(x: 1_138, y: 1_291, width: 918, height: 38)

        let notch = NotchGeometry.physicalNotchRect(
            screenFrame: screenFrame,
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: leftArea,
            auxiliaryTopRightArea: rightArea
        )

        XCTAssertEqual(notch, CGRect(x: 918, y: 1_291, width: 220, height: 38))
    }

    func testUsesFallbackWhenDisplayHasNoAuxiliaryTopAreas() {
        let notch = NotchGeometry.physicalNotchRect(
            screenFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            safeAreaInsets: NSEdgeInsets(),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        XCTAssertNil(notch)
    }

    func testRejectsMalformedAuxiliaryGap() {
        let frame = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let notch = NotchGeometry.physicalNotchRect(
            screenFrame: frame,
            safeAreaInsets: NSEdgeInsets(top: 24, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1_056, width: 960, height: 24),
            auxiliaryTopRightArea: CGRect(x: 960, y: 1_056, width: 960, height: 24)
        )

        XCTAssertNil(notch)
    }

    func testNotchedPanelKeepsWideInvisibleHitTargetAroundCameraHousing() {
        let frame = CGRect(x: 0, y: 0, width: 2_056, height: 1_329)
        let notch = CGRect(x: 918, y: 1_291, width: 220, height: 38)

        let layout = NotchGeometry.panelLayout(
            screenFrame: frame,
            physicalNotchRect: notch
        )

        XCTAssertEqual(
            layout.collapsedPanelRect,
            CGRect(x: 874, y: 1_273, width: 308, height: 56)
        )
        XCTAssertEqual(layout.collapsedPanelRect.maxY, frame.maxY)
        XCTAssertTrue(layout.collapsedPanelRect.contains(notch))
        XCTAssertEqual(layout.notchCutoutSize, CGSize(width: 224, height: 40))
        XCTAssertEqual(layout.contentTopInset, 56)
        XCTAssertEqual(
            layout.triggerRect,
            CGRect(x: 864, y: 1_263, width: 328, height: 66)
        )
        XCTAssertEqual(
            layout.expandedPanelRect,
            CGRect(x: 688, y: 891, width: 680, height: 438)
        )
    }

    func testFallbackPillAndExpandedShelfPreserveExternalDisplayOrigin() {
        let frame = CGRect(x: 2_056, y: 0, width: 1_920, height: 1_080)

        let layout = NotchGeometry.panelLayout(
            screenFrame: frame,
            physicalNotchRect: nil
        )

        XCTAssertEqual(
            layout.collapsedPanelRect,
            CGRect(x: 2_922, y: 1_050, width: 188, height: 30)
        )
        XCTAssertEqual(layout.notchCutoutSize, .zero)
        XCTAssertEqual(layout.contentTopInset, 30)
        XCTAssertEqual(
            layout.expandedPanelRect,
            CGRect(x: 2_676, y: 642, width: 680, height: 438)
        )
    }

    func testSurfaceCutoutIsCenteredAndExtendsPastTheTopEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 308, height: 56)
        let cutout = NotchShelfSurfaceShape.cutoutRect(
            in: bounds,
            cutoutSize: CGSize(width: 224, height: 40)
        )

        XCTAssertEqual(cutout, CGRect(x: 42, y: -1, width: 224, height: 41))
        XCTAssertEqual(cutout.midX, bounds.midX)
    }

    func testIdleRimHugsCutoutWithoutUsingTheFullHitTarget() {
        let bounds = CGRect(x: 0, y: 0, width: 308, height: 56)
        let rim = NotchShelfIdleRimShape.rimRect(
            in: bounds,
            cutoutSize: CGSize(width: 224, height: 40)
        )

        XCTAssertEqual(rim, CGRect(x: 42, y: 0.75, width: 224, height: 39.25))
        XCTAssertLessThan(rim.width, bounds.width)
        XCTAssertLessThan(rim.height, bounds.height)
    }
}
