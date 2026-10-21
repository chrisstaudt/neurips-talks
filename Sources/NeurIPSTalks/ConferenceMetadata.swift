import Foundation

enum ConferenceMetadata {
    static func load(from rawURL: String) async -> TalkDetails? {
        guard let resolved = ConferenceSite.resolveConferenceURL(from: rawURL) else { return nil }
        let fallback = fallbackDetails(from: resolved.url, site: resolved.site)

        do {
            var request = URLRequest(url: resolved.url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            request.setValue("Mozilla/5.0 NeurIPSTalks/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return fallback }
            return parse(html: html, source: resolved.url, site: resolved.site)
        } catch {
            return fallback
        }
    }

    static func parse(html: String, source: URL, site: ConferenceSite? = nil) -> TalkDetails {
        let resolvedSite = site ?? ConferenceSite.identify(source)
        var details = fallbackDetails(
            from: source,
            site: resolvedSite ?? ConferenceSite(identifier: source.host ?? "conference", name: "Conference", domains: [])
        )

        if let json = firstMatch(in: html, pattern: #"(?is)<script[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#),
           let jsonData = json.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: jsonData),
           let object = primaryJSONObject(in: value) {
            details = mergeJSONLD(object, into: details)
        }

        if details.speakers.isEmpty,
           let organizers = firstMatch(
               in: html,
               pattern: #"(?is)<div[^>]*class=[\"'][^\"']*event-organizers[^\"']*[\"'][^>]*>(.*?)</div>"#
           ) {
            let speakers = speakerNames(from: organizers)
            if !speakers.isEmpty {
                details = TalkDetails(
                    speakers: speakers,
                    conference: details.conference,
                    year: details.year,
                    eventType: details.eventType,
                    location: details.location
                )
            }
        }

        if let badge = firstMatch(
            in: html,
            pattern: #"(?is)<span[^>]*class=[\"'][^\"']*event-type-badge[^\"']*[\"'][^>]*>(.*?)</span>"#
        ), let eventType = normalizedEventType(from: text(from: badge)) {
            details = TalkDetails(
                speakers: details.speakers,
                conference: details.conference,
                year: details.year,
                eventType: eventType,
                location: details.location
            )
        }
        return details
    }

    private static func fallbackDetails(from url: URL, site: ConferenceSite) -> TalkDetails {
        let path = url.pathComponents.filter { $0 != "/" }
        let location: String? = path.firstIndex(of: "loc").flatMap { index in
            guard path.indices.contains(index + 1) else { return nil }
            return titleCase(path[index + 1])
        }
        let type = path.compactMap(eventType(for:)).first
        return TalkDetails(
            speakers: [],
            conference: site.name,
            year: ConferenceSite.year(in: url),
            eventType: type,
            location: location
        )
    }

    private static func primaryJSONObject(in value: Any) -> [String: Any]? {
        if let object = value as? [String: Any] {
            if let graph = object["@graph"] as? [[String: Any]] {
                return graph.first(where: { $0["author"] != nil }) ?? object
            }
            return object
        }
        if let objects = value as? [[String: Any]] {
            return objects.first(where: { $0["author"] != nil }) ?? objects.first
        }
        return nil
    }

    private static func mergeJSONLD(_ object: [String: Any], into details: TalkDetails) -> TalkDetails {
        let speakers: [String]
        if let authors = object["author"] as? [[String: Any]] {
            speakers = authors.compactMap { $0["name"] as? String }
        } else if let author = object["author"] as? [String: Any], let name = author["name"] as? String {
            speakers = [name]
        } else if let authors = object["author"] as? [String] {
            speakers = authors
        } else if let author = object["author"] as? String {
            speakers = [author]
        } else {
            speakers = []
        }
        let credit = object["creditText"] as? String
        let year = credit.flatMap { value in
            firstMatch(in: value, pattern: #"\b(20\d{2})\b"#).flatMap(Int.init)
        }
        let nonemptySpeakers = speakers.filter { !$0.isEmpty }
        return TalkDetails(
            speakers: nonemptySpeakers.isEmpty ? details.speakers : nonemptySpeakers,
            conference: details.conference,
            year: year ?? details.year,
            eventType: details.eventType,
            location: details.location
        )
    }

    private static func speakerNames(from html: String) -> [String] {
        let linkedNames = matches(
            in: html,
            pattern: #"(?is)<a[^>]*>(.*?)</a>"#
        ).map(text(from:)).filter { !$0.isEmpty }
        if !linkedNames.isEmpty { return linkedNames }

        return text(from: html)
            .components(separatedBy: CharacterSet(charactersIn: "·,\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedEventType(from value: String) -> String? {
        let lowered = value.lowercased()
        let types: [(String, String)] = [
            ("keynote", "Keynote"),
            ("invited talk", "Invited Talk"),
            ("tutorial", "Tutorial"),
            ("spotlight", "Spotlight"),
            ("oral", "Oral"),
            ("poster", "Poster"),
            ("workshop talk", "Workshop Talk"),
            ("workshop", "Workshop"),
            ("competition", "Competition"),
            ("social", "Social")
        ]
        return types.first(where: { lowered.contains($0.0) })?.1
    }

    private static func eventType(for slug: String) -> String? {
        switch slug.lowercased() {
        case "invited-talk": "Invited Talk"
        case "keynote-talk", "keynote": "Keynote"
        case "tutorial", "tutorials": "Tutorial"
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
        slug.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.capitalized }.joined(separator: " ")
    }

    private static func text(from html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<br\s*/?>|</p>|</li>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&middot;", with: "·")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\n\s*"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(in value: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
