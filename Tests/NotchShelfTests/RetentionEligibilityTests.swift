import Foundation
import XCTest
@testable import NotchShelf

final class RetentionEligibilityTests: XCTestCase {
    func testOldBaselineFileIsNeverEligibleButManagedCaptureIs() {
        let cutoff = Date(timeIntervalSinceReferenceDate: 10_000)
        let baseline = item(name: "baseline.png", key: "baseline", date: cutoff.addingTimeInterval(-10))
        let managed = item(name: "managed.png", key: "managed", date: cutoff.addingTimeInterval(-20))

        let expired = RetentionEligibility.expiredItems(
            in: [baseline, managed],
            managedCaptureKeys: ["managed"],
            cutoff: cutoff
        )

        XCTAssertEqual(expired.map(\.id), [managed.id])
    }

    func testPinnedAndRecentManagedCapturesRemainSafe() {
        let cutoff = Date(timeIntervalSinceReferenceDate: 10_000)
        var pinned = item(name: "pinned.png", key: "pinned", date: cutoff.addingTimeInterval(-10))
        pinned.isPinned = true
        let recent = item(name: "recent.png", key: "recent", date: cutoff.addingTimeInterval(1))

        let expired = RetentionEligibility.expiredItems(
            in: [pinned, recent],
            managedCaptureKeys: ["pinned", "recent"],
            cutoff: cutoff
        )

        XCTAssertTrue(expired.isEmpty)
    }

    private func item(name: String, key: String, date: Date) -> CaptureItem {
        CaptureItem(
            fileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            createdAt: date,
            modifiedAt: date,
            mediaType: .image,
            fileSize: 1,
            thumbnailCacheKey: key
        )
    }
}
