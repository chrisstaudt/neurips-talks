import Foundation

struct ConferenceSite: Equatable {
    let identifier: String
    let name: String
    let domains: [String]

    static let supported: [ConferenceSite] = [
        ConferenceSite(identifier: "neurips", name: "NeurIPS", domains: ["neurips.cc"]),
        ConferenceSite(identifier: "icml", name: "ICML", domains: ["icml.cc"]),
        ConferenceSite(identifier: "iclr", name: "ICLR", domains: ["iclr.cc"]),
        ConferenceSite(identifier: "aistats", name: "AISTATS", domains: ["aistats.org"]),
        ConferenceSite(identifier: "mlsys", name: "MLSys", domains: ["mlsys.org"]),
        ConferenceSite(identifier: "cvpr", name: "CVPR", domains: ["cvpr.thecvf.com"]),
        ConferenceSite(identifier: "iccv", name: "ICCV", domains: ["iccv.thecvf.com"]),
        ConferenceSite(identifier: "eccv", name: "ECCV", domains: ["eccv.ecva.net"]),
        ConferenceSite(identifier: "ijcai", name: "IJCAI", domains: ["ijcai.org"]),
        ConferenceSite(identifier: "chil", name: "CHIL", domains: ["chil.ahli.cc"])
    ]

    static func identify(_ url: URL) -> ConferenceSite? {
        guard let host = url.host?.lowercased() else { return nil }
        return supported.first { site in
            site.domains.contains { domain in
                host == domain || host.hasSuffix(".\(domain)")
            }
        }
    }

    static func resolveConferenceURL(from rawURL: String) -> (url: URL, site: ConferenceSite)? {
        guard let url = URL(string: rawURL) else { return nil }
        if let site = identify(url) { return (url, site) }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let embedded = components.queryItems?.first(where: { $0.name == "embed_parent_url" })?.value,
              let parent = URL(string: embedded),
              let site = identify(parent) else { return nil }
        return (parent, site)
    }

    static func year(in url: URL) -> Int? {
        let path = url.pathComponents.joined(separator: "/")
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\D)(20\d{2})(?:\D|$)"#),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range(at: 1), in: path) else { return nil }
        return Int(path[range])
    }
}
