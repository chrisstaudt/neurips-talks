import XCTest
@testable import NeurIPSTalks

final class TalkDownloaderTests: XCTestCase {
    func testClearlyTruncatedVideoIsRejected() {
        XCTAssertTrue(TalkDownloader.isClearlyIncomplete(actual: 980, expected: 3_592))
    }

    func testSmallDurationDifferenceIsAccepted() {
        XCTAssertFalse(TalkDownloader.isClearlyIncomplete(actual: 3_550, expected: 3_592))
    }

    func testInvalidDurationIsRejected() {
        XCTAssertTrue(TalkDownloader.isClearlyIncomplete(actual: 0, expected: 3_592))
    }
}
