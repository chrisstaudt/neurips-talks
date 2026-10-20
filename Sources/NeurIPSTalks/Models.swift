import Foundation

struct Slide: Codable, Hashable, Identifiable {
    let number: Int
    let title: String
    let start: Double
    let end: Double?
    let src: String

    var id: Int { number }
}

struct TalkDetails: Codable, Hashable {
    let speakers: [String]
    let conference: String?
    let year: Int?
    let eventType: String?
    let location: String?
}

struct PresentationManifest: Codable, Hashable {
    let title: String
    let speaker: String
    let source: String
    let duration: Double?
    let video: String?
    let slides: [Slide]
    let details: TalkDetails?

    var displaySpeakers: String {
        if let speakers = details?.speakers, !speakers.isEmpty {
            return speakers.joined(separator: " · ")
        }
        return speaker
    }

    var conferenceSummary: String {
        var parts: [String] = []
        if let conference = details?.conference {
            parts.append(details?.year.map { "\(conference) \($0)" } ?? conference)
        } else if let year = details?.year {
            parts.append(String(year))
        }
        if let eventType = details?.eventType { parts.append(eventType) }
        return parts.joined(separator: " · ")
    }
}

struct LibraryItem: Identifiable, Hashable {
    let folder: URL
    let manifest: PresentationManifest

    var id: String { folder.path }
}

enum BrowserCookies: String, CaseIterable, Identifiable {
    case none = "Public page"
    case chrome = "Chrome login"
    case safari = "Safari login"
    case firefox = "Firefox login"

    var id: String { rawValue }
    var argument: String? {
        switch self {
        case .none: nil
        case .chrome: "chrome"
        case .safari: "safari"
        case .firefox: "firefox"
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: String { rawValue }
    var height: Int {
        switch self {
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        }
    }
}
