import XCTest
@testable import NeurIPSTalks

final class ConferenceMetadataTests: XCTestCase {
    func testRecognizesSupportedConferenceDomains() throws {
        let cases: [(String, String)] = [
            ("https://neurips.cc/virtual/2025/109602", "NeurIPS"),
            ("https://icml.cc/virtual/2024/oral/35552", "ICML"),
            ("https://iclr.cc/virtual/2025/poster/30063", "ICLR"),
            ("https://virtual.aistats.org/virtual/2025/session/8800", "AISTATS"),
            ("https://mlsys.org/virtual/2025/poster/2985", "MLSys"),
            ("https://cvpr.thecvf.com/virtual/2025/poster/123", "CVPR"),
            ("https://iccv.thecvf.com/virtual/2025/poster/123", "ICCV"),
            ("https://eccv.ecva.net/virtual/2024/poster/123", "ECCV"),
            ("https://www.ijcai.org/virtual/2025/talk/123", "IJCAI"),
            ("https://chil.ahli.cc/virtual/2022/poster/123", "CHIL")
        ]

        for (value, expected) in cases {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(ConferenceSite.identify(url)?.name, expected, value)
        }
    }

    func testResolvesConferenceParentFromSlidesLiveEmbedURL() throws {
        let value = "https://slideslive.com/embed/presentation/38931344?embed_parent_url=https%3A%2F%2Ficml.cc%2Fvirtual%2F2020%2F7649"
        let resolved = try XCTUnwrap(ConferenceSite.resolveConferenceURL(from: value))

        XCTAssertEqual(resolved.site.name, "ICML")
        XCTAssertEqual(resolved.url.absoluteString, "https://icml.cc/virtual/2020/7649")
    }

    func testParsesSharedConferencePageMetadata() throws {
        let html = #"""
        <span class="event-type-badge"><span>Poster<br> in <br>Workshop: Systems</span></span>
        <div class="event-organizers">
          <a href="/profile/1">Theresa Eimer</a> · <a href="/profile/2">Ada Example</a>
        </div>
        """#
        let source = try XCTUnwrap(URL(string: "https://icml.cc/virtual/2020/7649"))

        let details = ConferenceMetadata.parse(html: html, source: source)

        XCTAssertEqual(details.conference, "ICML")
        XCTAssertEqual(details.year, 2020)
        XCTAssertEqual(details.eventType, "Poster")
        XCTAssertEqual(details.speakers, ["Theresa Eimer", "Ada Example"])
    }

    func testFindsYearInLegacyVirtualPath() throws {
        let source = try XCTUnwrap(URL(string: "https://iclr.cc/virtual_2020/poster_rJe2syrtvS.html"))
        XCTAssertEqual(ConferenceSite.year(in: source), 2020)
    }
}
