import Foundation
import XCTest
@testable import NotchShelf

final class CaptureGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testGroupsTodayYesterdayAndEarlierInReverseChronologicalOrder() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 10,
            hour: 14
        )))
        let todayMorning = try XCTUnwrap(calendar.date(byAdding: .hour, value: -3, to: now))
        let todayNoon = try XCTUnwrap(calendar.date(byAdding: .hour, value: -1, to: now))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let older = try XCTUnwrap(calendar.date(byAdding: .day, value: -4, to: now))

        let sections = CaptureGrouping.sections(
            from: [
                item(name: "older.png", date: older),
                item(name: "morning.png", date: todayMorning),
                item(name: "yesterday.png", date: yesterday),
                item(name: "noon.png", date: todayNoon),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].group, .today)
        XCTAssertEqual(sections[0].items.map(\.displayName), ["noon.png", "morning.png"])
        XCTAssertEqual(sections[1].group, .yesterday)
        XCTAssertEqual(sections[1].items.map(\.displayName), ["yesterday.png"])
        guard case .day(let date) = sections[2].group else {
            return XCTFail("Expected an earlier date group")
        }
        XCTAssertTrue(calendar.isDate(date, inSameDayAs: older))
    }

    func testNewestFirstUsesNameAsDeterministicTieBreaker() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let sorted = [
            item(name: "Capture 10.png", date: date),
            item(name: "Capture 2.png", date: date),
        ].sorted(by: CaptureGrouping.newestFirst)

        XCTAssertEqual(sorted.map(\.displayName), ["Capture 2.png", "Capture 10.png"])
    }

    func testFileStabilityRequiresThreeMatchingNonEmptySamples() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let stable = CaptureFileSnapshot(fileSize: 42, modifiedAt: date)

        XCTAssertFalse(CaptureFileStability.hasStableTail([stable, stable]))
        XCTAssertTrue(CaptureFileStability.hasStableTail([stable, stable, stable]))
        XCTAssertFalse(CaptureFileStability.hasStableTail([
            stable,
            CaptureFileSnapshot(fileSize: 43, modifiedAt: date),
            CaptureFileSnapshot(fileSize: 43, modifiedAt: date),
        ]))
        XCTAssertFalse(CaptureFileStability.hasStableTail([
            CaptureFileSnapshot(fileSize: 0, modifiedAt: date),
            CaptureFileSnapshot(fileSize: 0, modifiedAt: date),
            CaptureFileSnapshot(fileSize: 0, modifiedAt: date),
        ]))
    }

    private func item(name: String, date: Date) -> CaptureItem {
        CaptureItem(
            fileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            createdAt: date,
            modifiedAt: date,
            mediaType: .image,
            pixelWidth: 100,
            pixelHeight: 100,
            fileSize: 1_024,
            thumbnailCacheKey: name
        )
    }
}
