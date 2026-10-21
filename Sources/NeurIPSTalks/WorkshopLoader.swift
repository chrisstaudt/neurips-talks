import Foundation

enum WorkshopImportError: LocalizedError {
    case invalidURL
    case unreadablePage
    case noSchedule

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Paste a valid conference workshop URL."
        case .unreadablePage:
            "The workshop page could not be read. If it is restricted, make it public in a browser first and try again."
        case .noSchedule:
            "No workshop schedule was found on this page."
        }
    }
}

struct WorkshopLoader {
    typealias Update = @Sendable (String, Double) -> Void

    static func isWorkshopURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              ConferenceSite.identify(url) != nil else { return false }
        return url.pathComponents.contains { ["workshop", "workshops"].contains($0.lowercased()) }
    }

    static func load(
        from value: String,
        update: @escaping Update = { _, _ in }
    ) async throws -> WorkshopManifest {
        guard let url = URL(string: value) else { throw WorkshopImportError.invalidURL }
        update("Reading workshop schedule…", 0.08)
        let html = try await fetch(url)
        var manifest = try parse(html: html, source: url)

        // The workshop page contains the complete schedule, but detailed abstracts
        // live on the individual event pages. Fetch recorded entries in small
        // batches so the imported workshop remains useful offline without placing
        // excessive parallel load on the conference site.
        var abstracts: [String: String] = [:]
        let recorded = manifest.schedule.filter(\.hasVideo)
        update("Reading details for \(recorded.count) recordings…", 0.22)
        for start in stride(from: 0, to: recorded.count, by: 4) {
            let batch = Array(recorded[start ..< min(start + 4, recorded.count)])
            let values = await withTaskGroup(of: (String, String?).self, returning: [(String, String?)].self) { group in
                for segment in batch {
                    group.addTask {
                        guard let detailURL = URL(string: segment.url),
                              let detailHTML = try? await fetch(detailURL) else { return (segment.id, nil) }
                        return (segment.id, detailAbstract(in: detailHTML))
                    }
                }
                var values: [(String, String?)] = []
                for await value in group { values.append(value) }
                return values
            }
            for (id, abstract) in values {
                if let abstract, !abstract.isEmpty { abstracts[id] = abstract }
            }
            let completed = min(start + batch.count, recorded.count)
            update(
                "Reading recording details \(completed) of \(recorded.count)…",
                0.22 + 0.68 * Double(completed) / Double(max(recorded.count, 1))
            )
        }

        manifest = WorkshopManifest(
            title: manifest.title,
            source: manifest.source,
            abstract: manifest.abstract,
            organizers: manifest.organizers,
            conference: manifest.conference,
            year: manifest.year,
            location: manifest.location,
            schedule: manifest.schedule.map { segment in
                WorkshopSegment(
                    id: segment.id,
                    time: segment.time,
                    title: segment.title,
                    url: segment.url,
                    presentationID: segment.presentationID,
                    abstract: abstracts[segment.id] ?? segment.abstract
                )
            }
        )
        return manifest
    }

    static func parse(html: String, source: URL) throws -> WorkshopManifest {
        guard let rawTitle = firstMatch(
            in: html,
            pattern: #"(?is)<h1[^>]*class=[\"'][^\"']*event-title[^\"']*[\"'][^>]*>(.*?)</h1>"#
        ) else { throw WorkshopImportError.unreadablePage }

        let title = text(from: rawTitle)
        let workshopAbstract = firstMatch(
            in: html,
            pattern: #"(?is)<div[^>]*class=[\"'][^\"']*abstract-text-inner[^\"']*[\"'][^>]*>(.*?)</div>"#
        ).map(text(from:)) ?? ""
        let organizers = firstMatch(
            in: html,
            pattern: #"(?is)<div[^>]*class=[\"'][^\"']*event-organizers[^\"']*[\"'][^>]*>(.*?)</div>"#
        ).map(text(from:)) ?? ""

        let rowMatches = matches(
            in: html,
            pattern: #"(?is)<tr[^>]*class=[\"'][^\"']*schedule-row[^\"']*[\"'][^>]*id=[\"']wse-detail-(\d+)[\"'][^>]*>(.*?)</tr>"#
        )
        let schedule = rowMatches.compactMap { captures -> WorkshopSegment? in
            guard captures.count == 2 else { return nil }
            let id = captures[0]
            let row = captures[1]
            guard let linkParts = firstMatchGroups(
                in: row,
                pattern: #"(?is)<span[^>]*class=[\"'][^\"']*schedule-event-name[^\"']*[\"'][^>]*>\s*<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#
            ), linkParts.count == 2 else { return nil }
            let href = linkParts[0]
            let eventURL = URL(string: href, relativeTo: source)?.absoluteURL.absoluteString ?? href
            let time = firstMatch(
                in: row,
                pattern: #"(?is)<span[^>]*class=[\"'][^\"']*schedule-time[^\"']*[\"'][^>]*>(.*?)</span>"#
            ).map(text(from:)) ?? ""
            let presentationID = firstMatch(in: row, pattern: #"presentationId\s*:\s*[\"'](\d+)[\"']"#)
            return WorkshopSegment(
                id: id,
                time: time,
                title: text(from: linkParts[1]),
                url: eventURL,
                presentationID: presentationID,
                abstract: nil
            )
        }
        guard !schedule.isEmpty else { throw WorkshopImportError.noSchedule }

        let components = source.pathComponents.filter { $0 != "/" }
        let year = ConferenceSite.year(in: source)
        let location: String? = components.firstIndex(of: "loc").flatMap { index -> String? in
            guard components.indices.contains(index + 1) else { return nil }
            return components[index + 1].split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }
        return WorkshopManifest(
            title: title,
            source: source.absoluteString,
            abstract: workshopAbstract,
            organizers: organizers,
            conference: ConferenceSite.identify(source)?.name ?? "Conference",
            year: year,
            location: location,
            schedule: schedule
        )
    }

    private static func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 NeurIPSTalks/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { throw WorkshopImportError.unreadablePage }
        return html
    }

    private static func detailAbstract(in html: String) -> String? {
        firstMatch(
            in: html,
            pattern: #"(?is)<div[^>]*class=[\"'][^\"']*abstract-text-inner[^\"']*[\"'][^>]*>(.*?)</div>"#
        ).map(text(from:))
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
        firstMatchGroups(in: value, pattern: pattern)?.first
    }

    private static func firstMatchGroups(in value: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1 else { return nil }
        return (1 ..< match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func matches(in value: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
            (1 ..< match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: value) else { return nil }
                return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
