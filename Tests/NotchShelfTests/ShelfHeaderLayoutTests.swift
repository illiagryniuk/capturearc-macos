import XCTest
@testable import NotchShelf

final class ShelfHeaderLayoutTests: XCTestCase {
    func testNarrowWidthKeepsFullActionRailAndTitleReserve() {
        XCTAssertEqual(ShelfHeaderMetrics.navigationBudget(width: 200, actions: 60, titleIdeal: 95), 60)
    }

    func testLongLocalizedTitleDoesNotShrinkNavigationBudget() {
        XCTAssertEqual(ShelfHeaderMetrics.navigationBudget(width: 280, actions: 30, titleIdeal: 180),
                       ShelfHeaderMetrics.navigationBudget(width: 280, actions: 30, titleIdeal: 64))
    }

    func testNormalWidthCanUseFullLabels() {
        XCTAssertEqual(ShelfHeaderMetrics.navigationBudget(width: 396, actions: 80, titleIdeal: 98), 236)
    }

    func testDegenerateWidthDoesNotProposeNegativeSpace() {
        XCTAssertEqual(ShelfHeaderMetrics.navigationBudget(width: 50, actions: 60, titleIdeal: 95), 0)
    }
}
