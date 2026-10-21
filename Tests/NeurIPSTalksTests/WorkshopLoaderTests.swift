import XCTest
@testable import NeurIPSTalks

final class WorkshopLoaderTests: XCTestCase {
    func testParsesWorkshopScheduleAndVideoAvailability() throws {
        let html = #"""
        <h1 class="event-title">ML &amp; Systems</h1>
        <div class="event-organizers">Ada Example &middot; Ben Example</div>
        <div class="abstract-text-inner"><p>A workshop about useful systems.</p></div>
        <tr class="schedule-row" id="wse-detail-101">
          <span class="schedule-time">8:30 AM</span>
          <span class="schedule-event-name"><a href="/virtual/2025/101">Opening Remarks</a></span>
          <script>presentationId: '39050001'</script>
        </tr>
        <tr class="schedule-row" id="wse-detail-102">
          <span class="schedule-time">9:00 AM</span>
          <span class="schedule-event-name"><a href="/virtual/2025/102">Coffee Break</a></span>
        </tr>
        """#
        let source = try XCTUnwrap(URL(string: "https://neurips.cc/virtual/2025/loc/san-diego/workshop/109537"))

        let workshop = try WorkshopLoader.parse(html: html, source: source)

        XCTAssertEqual(workshop.title, "ML & Systems")
        XCTAssertEqual(workshop.organizers, "Ada Example · Ben Example")
        XCTAssertEqual(workshop.year, 2025)
        XCTAssertEqual(workshop.location, "San Diego")
        XCTAssertEqual(workshop.schedule.count, 2)
        XCTAssertEqual(workshop.schedule[0].url, "https://neurips.cc/virtual/2025/101")
        XCTAssertEqual(workshop.schedule[0].presentationID, "39050001")
        XCTAssertTrue(workshop.schedule[0].hasVideo)
        XCTAssertFalse(workshop.schedule[1].hasVideo)
    }

    func testWorkshopURLRecognition() {
        XCTAssertTrue(WorkshopLoader.isWorkshopURL("https://neurips.cc/virtual/2025/loc/san-diego/workshop/109537"))
        XCTAssertTrue(WorkshopLoader.isWorkshopURL("https://icml.cc/virtual/2025/workshops/12345"))
        XCTAssertFalse(WorkshopLoader.isWorkshopURL("https://neurips.cc/virtual/2025/invited-talk/109602"))
        XCTAssertFalse(WorkshopLoader.isWorkshopURL("https://slideslive.com/39055728"))
    }
}
