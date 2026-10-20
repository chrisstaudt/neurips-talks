import Foundation

enum NeurIPSMetadata {
    static func load(from rawURL: String) async -> TalkDetails? {
        guard let url = neuripsURL(from: rawURL) else { return nil }
        var details = fallbackDetails(from: url)

        do {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            request.setValue("Mozilla/5.0 NeurIPSTalks/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return details }

            if let json = firstMatch(in: html, pattern: #"(?is)<script[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#),
               let jsonData = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                details = mergeJSONLD(object, into: details)
            }

            if let type = firstMatch(
                in: html,
                pattern: #"(?is)<span[^>]*class=[\"'][^\"']*event-type-badge[^\"']*[\"'][^>]*>\s*([^<]+?)\s*</span>"#
            ) {
                details = TalkDetails(
                    speakers: details.speakers,
                    conference: details.conference,
                    year: details.year,
                    eventType: decodeHTML(type),
                    location: details.location
                )
            }
            return details
        } catch {
            return details
        }
    }

    private static func neuripsURL(from rawURL: String) -> URL? {
        guard let url = URL(string: rawURL) else { return nil }
        if url.host?.lowercased().hasSuffix("neurips.cc") == true { return url }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let embedded = components.queryItems?.first(where: { $0.name == "embed_parent_url" })?.value,
              let parent = URL(string: embedded),
              parent.host?.lowercased().hasSuffix("neurips.cc") == true else { return nil }
        return parent
    }

    private static func fallbackDetails(from url: URL) -> TalkDetails {
        let path = url.pathComponents.filter { $0 != "/" }
        let year: Int? = path.firstIndex(of: "virtual").flatMap { index in
            guard path.indices.contains(index + 1) else { return nil }
            return Int(path[index + 1])
        }
        let location: String? = path.firstIndex(of: "loc").flatMap { index in
            guard path.indices.contains(index + 1) else { return nil }
            return titleCase(path[index + 1])
        }
        let type = path.compactMap(eventType(for:)).first
        return TalkDetails(speakers: [], conference: "NeurIPS", year: year, eventType: type, location: location)
    }

    private static func mergeJSONLD(_ object: [String: Any], into details: TalkDetails) -> TalkDetails {
        let authorObjects: [[String: Any]]
        if let authors = object["author"] as? [[String: Any]] { authorObjects = authors }
        else if let author = object["author"] as? [String: Any] { authorObjects = [author] }
        else { authorObjects = [] }
        let speakers = authorObjects.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
        let credit = object["creditText"] as? String
        let conference = credit?.components(separatedBy: .decimalDigits).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let year = credit.flatMap { value in
            firstMatch(in: value, pattern: #"\b(20\d{2})\b"#).flatMap(Int.init)
        }
        return TalkDetails(
            speakers: speakers.isEmpty ? details.speakers : speakers,
            conference: conference?.isEmpty == false ? conference : details.conference,
            year: year ?? details.year,
            eventType: details.eventType,
            location: details.location
        )
    }

    private static func eventType(for slug: String) -> String? {
        switch slug.lowercased() {
        case "invited-talk": "Invited Talk"
        case "keynote-talk": "Keynote"
        case "tutorial": "Tutorial"
        case "workshop", "workshops": "Workshop"
        case "workshop-talk": "Workshop Talk"
        case "oral": "Oral"
        case "poster": "Poster"
        case "spotlight": "Spotlight"
        case "competition": "Competition"
        case "affinity-event": "Affinity Event"
        case "social": "Social"
        default: nil
        }
    }

    private static func titleCase(_ slug: String) -> String {
        slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
