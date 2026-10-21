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
    let workshop: WorkshopManifest?
    let workshopTalks: [LibraryItem]

    init(
        folder: URL,
        manifest: PresentationManifest,
        workshop: WorkshopManifest? = nil,
        workshopTalks: [LibraryItem] = []
    ) {
        self.folder = folder
        self.manifest = manifest
        self.workshop = workshop
        self.workshopTalks = workshopTalks
    }

    var id: String { folder.path }
    var isWorkshop: Bool { workshop != nil }

    func downloadedTalk(for segment: WorkshopSegment) -> LibraryItem? {
        workshopTalks.first {
            $0.manifest.source == segment.url ||
            $0.manifest.source == "https://slideslive.com/\(segment.presentationID ?? "")"
        }
    }
}

struct WorkshopManifest: Codable, Hashable {
    let title: String
    let source: String
    let abstract: String
    let organizers: String
    let conference: String
    let year: Int?
    let location: String?
    let schedule: [WorkshopSegment]
}

struct WorkshopSegment: Codable, Hashable, Identifiable {
    let id: String
    let time: String
    let title: String
    let url: String
    let presentationID: String?
    let abstract: String?

    var hasVideo: Bool { presentationID?.isEmpty == false }
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
