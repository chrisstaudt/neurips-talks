import AVFoundation
import Foundation

enum TalkDownloadError: LocalizedError {
    case toolMissing
    case commandFailed(String)
    case invalidMetadata
    case noSlides
    case noVideo
    case incompleteVideo(actual: Double, expected: Double)
    case mergeFailed(String)
    case outputExists(URL)

    var errorDescription: String? {
        switch self {
        case .toolMissing:
            "The bundled downloader is missing. Rebuild the app with ./build_app.sh --download-tools."
        case .commandFailed(let detail): "Downloader failed:\n\(Self.conciseFailure(detail))"
        case .invalidMetadata: "The page did not contain a readable SlidesLive presentation."
        case .noSlides: "This presentation does not expose synchronized slides."
        case .noVideo: "No compatible video and audio streams were found."
        case .incompleteVideo(let actual, let expected):
            "The downloaded video is incomplete (\(clock(actual)) of about \(clock(expected))). Its slides were kept; resume the download to repair the video."
        case .mergeFailed(let detail): "Could not combine video and audio: \(detail)"
        case .outputExists(let url): "A download with this name already exists at \(url.path)."
        }
    }

    private func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func conciseFailure(_ detail: String) -> String {
        let lines = detail
            .split(whereSeparator: \Character.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let diagnosticLines = lines.filter {
            let lowered = $0.lowercased()
            return lowered.contains("error") || lowered.contains("failed") || lowered.contains("unable")
        }
        let useful = diagnosticLines.isEmpty ? Array(lines.suffix(6)) : Array(diagnosticLines.suffix(6))
        return useful.isEmpty ? "No diagnostic details were returned." : useful.joined(separator: "\n")
    }
}

final class DownloadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var activeProcess: Process?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func check() throws {
        if isCancelled || Task.isCancelled { throw CancellationError() }
    }

    func register(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        activeProcess = process
    }

    func unregister(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if activeProcess === process { activeProcess = nil }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = activeProcess
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}

struct TalkDownloader {
    typealias Update = @Sendable (String, Double?) -> Void

    static func download(
        pageURL: String,
        library: URL,
        cookiesFrom: String?,
        maxHeight: Int,
        cancellation: DownloadCancellation,
        discoveredPresentation: @escaping @Sendable (String, URL) -> Void,
        update: @escaping Update
    ) async throws -> URL {
        try cancellation.check()
        let tool = try downloaderURL()
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        var common = ["--no-warnings"]
        if let cookiesFrom { common += ["--cookies-from-browser", cookiesFrom] }

        update("Reading SlidesLive metadata…", 0.02)
        let metadataResult = try run(
            tool,
            arguments: common + ["--skip-download", "--dump-single-json", pageURL],
            cancellation: cancellation
        )
        guard let root = try JSONSerialization.jsonObject(with: metadataResult.data(using: .utf8) ?? Data()) as? [String: Any],
              let metadata = mainEntry(root) else { throw TalkDownloadError.invalidMetadata }

        let title = metadata["title"] as? String ?? "SlidesLive Talk"
        let talkID = String(describing: metadata["id"] ?? "")
        let output = library.appendingPathComponent(safeName("\(talkID)-\(title)"), isDirectory: true)
        discoveredPresentation(title, output)
        update("Reading conference details…", 0.04)
        var talkDetails = await ConferenceMetadata.load(from: pageURL)
        try cancellation.check()
        let fallbackSpeaker = metadata["uploader"] as? String ?? metadata["channel"] as? String ?? ""
        if !fallbackSpeaker.isEmpty, talkDetails?.speakers.isEmpty != false {
            if let existing = talkDetails {
                talkDetails = TalkDetails(
                    speakers: [fallbackSpeaker],
                    conference: existing.conference,
                    year: existing.year,
                    eventType: existing.eventType,
                    location: existing.location
                )
            } else {
                talkDetails = TalkDetails(
                    speakers: [fallbackSpeaker],
                    conference: nil,
                    year: nil,
                    eventType: nil,
                    location: nil
                )
            }
        }
        if FileManager.default.fileExists(atPath: output.appendingPathComponent("presentation.json").path) {
            throw TalkDownloadError.outputExists(output)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        do {
            let slideInfo = try slideRecords(metadata)
            let slidesFolder = output.appendingPathComponent("slides", isDirectory: true)
            try FileManager.default.createDirectory(at: slidesFolder, withIntermediateDirectories: true)
            var slides: [Slide] = []
            for (index, record) in slideInfo.enumerated() {
                try cancellation.check()
                let fraction = 0.05 + (Double(index) / Double(max(1, slideInfo.count))) * 0.20
                update("Downloading slide \(index + 1) of \(slideInfo.count)…", fraction)
                let ext = URL(string: record.url)?.pathExtension.lowercased() ?? "png"
                let safeExtension = ["png", "jpg", "jpeg", "webp"].contains(ext) ? ext : "png"
                let fileName = String(format: "%03d.%@", index + 1, safeExtension)
                let slideFile = slidesFolder.appendingPathComponent(fileName)
                if !hasUsableFile(at: slideFile) {
                    let (data, _) = try await URLSession.shared.data(from: currentSlideURL(record.url))
                    try cancellation.check()
                    try data.write(to: slideFile, options: .atomic)
                }
                slides.append(Slide(
                    number: index + 1,
                    title: record.title,
                    start: record.start,
                    end: record.end,
                    src: "slides/\(fileName)"
                ))
            }

            let formats = metadata["formats"] as? [[String: Any]] ?? []
            let duration = (metadata["duration"] as? NSNumber)?.doubleValue
            guard let videoFormat = bestVideo(in: formats, maxHeight: maxHeight) else { throw TalkDownloadError.noVideo }
            let audioFormat = bestAudio(in: formats)
            let videoID = videoFormat["format_id"] as? String ?? ""
            let videoHasAudio = codec(videoFormat["acodec"]) != "none"
            let playlistSelection = primaryPlaylistSelection(for: metadata)
            let videoTemplate = output.appendingPathComponent("video-track.%(ext)s").path
            update("Downloading presenter video…", 0.28)
            try runStreaming(
                tool,
                arguments: common + playlistSelection + ["--newline", "--format", videoID, "--output", videoTemplate, pageURL],
                phaseStart: 0.28,
                phaseSize: videoHasAudio ? 0.67 : 0.43,
                label: "Downloading presenter video",
                cancellation: cancellation,
                update: update
            )
            guard let videoTrack = newestFile(in: output, prefix: "video-track.") else { throw TalkDownloadError.noVideo }

            let finalVideo: URL
            if videoHasAudio || audioFormat == nil {
                finalVideo = output.appendingPathComponent("video.\(videoTrack.pathExtension)")
                // A previous attempt may have produced a playable but truncated final
                // file. A newly completed track must always replace it.
                try? FileManager.default.removeItem(at: finalVideo)
                try FileManager.default.moveItem(at: videoTrack, to: finalVideo)
            } else {
                let audioID = audioFormat?["format_id"] as? String ?? ""
                let audioTemplate = output.appendingPathComponent("audio-track.%(ext)s").path
                update("Downloading audio…", 0.72)
                try runStreaming(
                    tool,
                    arguments: common + playlistSelection + ["--newline", "--format", audioID, "--output", audioTemplate, pageURL],
                    phaseStart: 0.72,
                    phaseSize: 0.20,
                    label: "Downloading audio",
                    cancellation: cancellation,
                    update: update
                )
                guard let audioTrack = newestFile(in: output, prefix: "audio-track.") else { throw TalkDownloadError.noVideo }
                finalVideo = output.appendingPathComponent("video.mp4")
                update("Combining video and audio…", 0.94)
                try cancellation.check()
                try? FileManager.default.removeItem(at: finalVideo)
                try await merge(video: videoTrack, audio: audioTrack, output: finalVideo)
                try cancellation.check()
                try? FileManager.default.removeItem(at: videoTrack)
                try? FileManager.default.removeItem(at: audioTrack)
            }

            update("Verifying video…", 0.98)
            try await validateDuration(of: finalVideo, expected: duration)
            try cancellation.check()
            let manifest = PresentationManifest(
                title: title,
                speaker: talkDetails?.speakers.joined(separator: " · ") ?? fallbackSpeaker,
                source: pageURL,
                duration: duration,
                video: finalVideo.lastPathComponent,
                slides: slides,
                details: talkDetails
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: output.appendingPathComponent("presentation.json"), options: .atomic)
            update("Finishing…", 0.99)
            return output
        } catch { throw error }
    }

    private static func downloaderURL() throws -> URL {
        if let bundled = Bundle.main.url(forResource: "yt-dlp", withExtension: nil, subdirectory: "Tools") {
            return bundled
        }
        for path in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw TalkDownloadError.toolMissing
    }

    private static func run(
        _ executable: URL,
        arguments: [String],
        cancellation: DownloadCancellation
    ) throws -> String {
        try cancellation.check()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try cancellation.register(process)
        defer { cancellation.unregister(process) }
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try cancellation.check()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw TalkDownloadError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return output
    }

    private static func runStreaming(
        _ executable: URL,
        arguments: [String],
        phaseStart: Double,
        phaseSize: Double,
        label: String,
        cancellation: DownloadCancellation,
        update: Update
    ) throws {
        try cancellation.check()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try cancellation.register(process)
        defer { cancellation.unregister(process) }
        try process.run()
        var collected = ""
        while process.isRunning {
            try cancellation.check()
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            let text = String(decoding: data, as: UTF8.self)
            collected += text
            if let match = text.range(of: #"\d+(?:\.\d+)?%"#, options: .regularExpression),
               let percent = Double(text[match].dropLast()) {
                update("\(label)… \(Int(percent))%", phaseStart + phaseSize * percent / 100)
            }
        }
        collected += String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        try cancellation.check()
        guard process.terminationStatus == 0 else { throw TalkDownloadError.commandFailed(collected.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func mainEntry(_ root: [String: Any]) -> [String: Any]? {
        if root["_type"] as? String == "playlist", let entries = root["entries"] as? [[String: Any]] {
            return entries.first { ($0["chapters"] as? [Any])?.isEmpty == false } ?? entries.first
        }
        return root
    }

    private struct SlideRecord {
        let title: String
        let start: Double
        let end: Double?
        let url: String
    }

    private static func slideRecords(_ metadata: [String: Any]) throws -> [SlideRecord] {
        let thumbnails = metadata["thumbnails"] as? [[String: Any]] ?? []
        var byID: [String: String] = [:]
        for thumbnail in thumbnails {
            let id = String(describing: thumbnail["id"] ?? "")
            if id != "cover", let url = thumbnail["url"] as? String { byID[id] = url }
        }
        let chapters = metadata["chapters"] as? [[String: Any]] ?? []
        let fallback = thumbnails.compactMap { item -> String? in
            String(describing: item["id"] ?? "") == "cover" ? nil : item["url"] as? String
        }
        var result: [SlideRecord] = []
        for (index, chapter) in chapters.enumerated() {
            let title = chapter["title"] as? String ?? "Slide \(index + 1)"
            let id = String(format: "%03d", index + 1)
            guard let url = byID[id] ?? (index < fallback.count ? fallback[index] : nil) else { continue }
            result.append(SlideRecord(
                title: title,
                start: (chapter["start_time"] as? NSNumber)?.doubleValue ?? 0,
                end: (chapter["end_time"] as? NSNumber)?.doubleValue,
                url: url
            ))
        }
        guard !result.isEmpty else { throw TalkDownloadError.noSlides }
        return result
    }

    private static func currentSlideURL(_ value: String) -> URL {
        guard var components = URLComponents(string: value) else { return URL(string: value)! }
        if components.host == "slides.slideslive.com" {
            components.host = "slideslive-slides.b-cdn.net"
            components.queryItems = [URLQueryItem(name: "class", value: "2160")]
        }
        return components.url!
    }

    private static func codec(_ value: Any?) -> String { value as? String ?? "none" }

    static func primaryPlaylistSelection(for metadata: [String: Any]) -> [String] {
        if let index = (metadata["playlist_index"] as? NSNumber)?.intValue, index > 0 {
            return ["--playlist-items", String(index)]
        }
        return ["--no-playlist"]
    }

    private static func bestVideo(in formats: [[String: Any]], maxHeight: Int) -> [String: Any]? {
        let videos = formats.filter {
            codec($0["vcodec"]) != "none" && (($0["height"] as? NSNumber)?.intValue ?? 0) <= maxHeight
        }
        return videos.max {
            let lhs = (($0["height"] as? NSNumber)?.doubleValue ?? 0) * 10_000 + (($0["tbr"] as? NSNumber)?.doubleValue ?? 0)
            let rhs = (($1["height"] as? NSNumber)?.doubleValue ?? 0) * 10_000 + (($1["tbr"] as? NSNumber)?.doubleValue ?? 0)
            return lhs < rhs
        }
    }

    private static func bestAudio(in formats: [[String: Any]]) -> [String: Any]? {
        formats.filter { codec($0["vcodec"]) == "none" && codec($0["acodec"]) != "none" }
            .max { (($0["abr"] as? NSNumber)?.doubleValue ?? 0) < (($1["abr"] as? NSNumber)?.doubleValue ?? 0) }
    }

    private static func newestFile(in folder: URL, prefix: String) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(prefix) && !$0.lastPathComponent.hasSuffix(".part") }
            .max { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast < (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
    }

    private static func hasUsableFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }

    static func mediaDuration(at url: URL) async -> Double? {
        do {
            let time = try await AVURLAsset(url: url).load(.duration)
            let seconds = time.seconds
            return seconds.isFinite && seconds > 0 ? seconds : nil
        } catch {
            return nil
        }
    }

    static func isClearlyIncomplete(actual: Double, expected: Double) -> Bool {
        guard actual.isFinite, expected.isFinite, actual > 0, expected > 0 else { return true }
        // Allow metadata/stream rounding and short bumpers, while rejecting genuinely
        // truncated HLS downloads such as a 16-minute file for a 60-minute talk.
        let tolerance = max(30, expected * 0.05)
        return actual + tolerance < expected
    }

    private static func validateDuration(of url: URL, expected: Double?) async throws {
        guard let expected, expected > 0 else { return }
        guard let actual = await mediaDuration(at: url) else { throw TalkDownloadError.noVideo }
        if isClearlyIncomplete(actual: actual, expected: expected) {
            throw TalkDownloadError.incompleteVideo(actual: actual, expected: expected)
        }
    }

    private static func merge(video: URL, audio: URL, output: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let sourceVideo = videoTracks.first, let sourceAudio = audioTracks.first else { throw TalkDownloadError.noVideo }
        let duration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let targetVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let targetAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TalkDownloadError.mergeFailed("Could not create media tracks.")
        }
        try targetVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        try targetAudio.insertTimeRange(CMTimeRange(start: .zero, duration: min(duration, audioDuration)), of: sourceAudio, at: .zero)
        targetVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw TalkDownloadError.mergeFailed("The system exporter is unavailable.")
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        let exporterBox = ExportSessionBox(exporter)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                exporterBox.value.exportAsynchronously {
                    switch exporterBox.value.status {
                    case .completed: continuation.resume()
                    case .failed, .cancelled: continuation.resume(throwing: TalkDownloadError.mergeFailed(exporterBox.value.error?.localizedDescription ?? "Unknown export error"))
                    default: continuation.resume(throwing: TalkDownloadError.mergeFailed("Unexpected export state"))
                    }
                }
            }
        } onCancel: {
            exporterBox.value.cancelExport()
        }
    }

    private static func safeName(_ value: String) -> String {
        let invalid = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted
        let parts = value.components(separatedBy: invalid).filter { !$0.isEmpty }
        return String(parts.joined(separator: "-").prefix(100)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
