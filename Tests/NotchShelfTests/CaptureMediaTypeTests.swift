import UniformTypeIdentifiers
import XCTest
@testable import NotchShelf

final class CaptureMediaTypeTests: XCTestCase {
    func testClassifiesImageAndMovieUniformTypes() {
        XCTAssertEqual(CaptureMediaType.classify(.png), .image)
        XCTAssertEqual(CaptureMediaType.classify(.jpeg), .image)
        XCTAssertEqual(CaptureMediaType.classify(.quickTimeMovie), .video)
        XCTAssertEqual(CaptureMediaType.classify(.mpeg4Movie), .video)
    }

    func testRejectsTypesThatAreNotImagesOrMovies() {
        XCTAssertNil(CaptureMediaType.classify(.plainText))
        XCTAssertNil(CaptureMediaType.classify(.pdf))
        XCTAssertNil(CaptureMediaType.classify(.folder))
    }

    func testURLClassificationUsesUniformTypeResolution() {
        XCTAssertEqual(
            CaptureMediaType.classify(url: URL(fileURLWithPath: "/tmp/Localized Name.heic")),
            .image
        )
        XCTAssertEqual(
            CaptureMediaType.classify(url: URL(fileURLWithPath: "/tmp/Renamed Capture.mov")),
            .video
        )
        XCTAssertNil(
            CaptureMediaType.classify(url: URL(fileURLWithPath: "/tmp/Screenshot Notes.txt"))
        )
    }
}
