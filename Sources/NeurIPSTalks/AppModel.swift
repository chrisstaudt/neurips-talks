import AppKit
import Foundation

@MainActor
final class DownloadJob: ObservableObject, Identifiable {
    let id: UUID
    @Published var url: String
    let cookieSource: BrowserCookies
    let quality: VideoQuality
    @Published var title: String
    @Published var progress: Double = 0
    @Published var status = "Waiting…"
    @Published var error: String?
    @Published var folder: URL?
    @Published var partialFolder: URL?
    @Published var isFinished = false
    @Published var isCancelled = false
    @Published var needsRepair = false

    init(
        id: UUID = UUID(),
        url: String,
        title: String? = nil,
        cookieSource: BrowserCookies,
        quality: VideoQuality
    ) {
        self.id = id
        self.url = url
        self.cookieSource = cookieSource
        self.quality = quality
        self.title = title ?? URL(string: url)?.host ?? url
    }
}

private struct PersistedDownloadJob: Codable {
    let id: UUID
    let url: String
    let title: String
    let progress: Double
    let cookieSource: String
    let quality: String
    let partialFolderPath: String?
    let needsRepair: Bool?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var library: [LibraryItem] = []
    @Published var selected: LibraryItem?
    @Published var showingDownloader = false
    @Published var downloadURL = ""
    @Published var cookieSource: BrowserCookies = .none
    @Published var quality: VideoQuality = .p1080
    @Published var jobs: [DownloadJob] = []
    @Published var lastError: String?

    private let defaultsKey = "libraryDirectory"
    private let pendingDownloadsKey = "pendingDownloads"
    private var downloadTasks: [UUID: Task<Void, Never>] = [:]

    var libraryDirectory: URL {
        if let saved = UserDefaults.standard.string(forKey: defaultsKey) {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("NeurIPS Talks", isDirectory: true)
    }

    init() {
        refreshLibrary()
        restorePendingDownloads()
        discoverLegacyIncompleteDownloads()
        Task { await auditCompletedDownloads() }
    }

    func refreshLibrary(selecting folder: URL? = nil) {
        try? FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: libraryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        library = folders.compactMap { folder in
            let manifestURL = folder.appendingPathComponent("presentation.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(PresentationManifest.self, from: data) else { return nil }
            return LibraryItem(folder: folder, manifest: manifest)
        }.sorted { $0.manifest.title.localizedStandardCompare($1.manifest.title) == .orderedAscending }

        if let folder {
            selected = library.first { $0.folder.standardizedFileURL == folder.standardizedFileURL }
            showingDownloader = false
        }
    }

    func chooseLibraryDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Talk Library"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = libraryDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        selected = nil
        refreshLibrary()
    }

    func revealLibrary() {
        try? FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([libraryDirectory])
    }

    func openDownloadedTalk(_ folder: URL) {
        refreshLibrary()
        selected = library.first { $0.folder.standardizedFileURL == folder.standardizedFileURL }
        showingDownloader = false
    }

    func clearCompletedJobs() {
        jobs.removeAll { $0.folder != nil }
        persistPendingDownloads()
    }

    func removePartialDownload(_ job: DownloadJob) {
        guard job.isFinished, job.folder == nil else { return }
        if let partialFolder = job.partialFolder {
            let root = libraryDirectory.standardizedFileURL
            let target = partialFolder.standardizedFileURL
            guard target != root, target.deletingLastPathComponent() == root else {
                lastError = "The partial download is outside the current library and was not removed."
                return
            }
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
            } catch {
                lastError = "Could not remove the partial download: \(error.localizedDescription)"
                return
            }
        }
        jobs.removeAll { $0.id == job.id }
        lastError = nil
        persistPendingDownloads()
    }

    func startDownload() {
        let input = downloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, URL(string: input) != nil else {
            lastError = "Paste a valid NeurIPS or SlidesLive URL."
            return
        }
        lastError = nil
        if let existing = jobs.first(where: { $0.url == input && $0.folder == nil }) {
            if existing.isFinished { resumeDownload(existing) }
            else { lastError = "That talk is already in the download queue." }
            downloadURL = ""
            return
        }
        let job = DownloadJob(url: input, cookieSource: cookieSource, quality: quality)
        jobs.insert(job, at: 0)
        downloadURL = ""
        persistPendingDownloads()
        launchDownload(job)
    }

    func cancelDownload(_ job: DownloadJob) {
        guard !job.isFinished else { return }
        job.status = "Cancelling…"
        persistPendingDownloads()
        downloadTasks[job.id]?.cancel()
    }

    func resumeDownload(_ job: DownloadJob) {
        guard job.isFinished, job.folder == nil else { return }
        if job.needsRepair, let folder = job.partialFolder {
            do {
                try FileManager.default.removeItem(at: folder.appendingPathComponent("presentation.json"))
            } catch CocoaError.fileNoSuchFile {
                // It may already have been prepared for repair before the app quit.
            } catch {
                lastError = "Could not prepare the damaged download for repair: \(error.localizedDescription)"
                return
            }
            job.needsRepair = false
        }
        launchDownload(job)
    }

    private func launchDownload(_ job: DownloadJob) {
        job.progress = 0
        job.status = "Reading presentation…"
        job.error = nil
        job.folder = nil
        job.isFinished = false
        job.isCancelled = false
        let destination = libraryDirectory
        let cookies = job.cookieSource.argument
        let maxHeight = job.quality.height
        let jobID = job.id
        let input = job.url
        let cancellation = DownloadCancellation()

        let task = Task.detached(priority: .userInitiated) {
            do {
                let folder = try await withTaskCancellationHandler {
                    try await TalkDownloader.download(
                        pageURL: input,
                        library: destination,
                        cookiesFrom: cookies,
                        maxHeight: maxHeight,
                        cancellation: cancellation,
                        discoveredPresentation: { title, folder in
                            Task { @MainActor in
                                self.updateJobMetadata(jobID, title: title, partialFolder: folder)
                            }
                        },
                        update: { message, fraction in
                            Task { @MainActor in
                                self.updateJob(jobID, status: message, progress: fraction)
                            }
                        }
                    )
                } onCancel: {
                    cancellation.cancel()
                }
                await self.finishJob(jobID, folder: folder)
            } catch {
                if cancellation.isCancelled || error is CancellationError {
                    await self.cancelledJob(jobID)
                } else {
                    await self.failJob(jobID, message: error.localizedDescription)
                }
            }
        }
        downloadTasks[jobID] = task
        persistPendingDownloads()
    }

    private func updateJob(_ id: UUID, status: String, progress: Double?) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.status = status
        if let progress { job.progress = progress }
        persistPendingDownloads()
    }

    private func updateJobMetadata(_ id: UUID, title: String, partialFolder: URL) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.title = title
        job.partialFolder = partialFolder
        persistPendingDownloads()
    }

    private func finishJob(_ id: UUID, folder: URL) {
        downloadTasks.removeValue(forKey: id)
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.folder = folder
        job.partialFolder = nil
        job.progress = 1
        job.status = "Ready to watch"
        job.isFinished = true
        job.needsRepair = false
        if let item = loadItem(at: folder) {
            job.title = item.manifest.title
        }
        persistPendingDownloads()
        refreshLibrary()
    }

    private func failJob(_ id: UUID, message: String) {
        downloadTasks.removeValue(forKey: id)
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.error = message
        job.status = "Download failed"
        job.isFinished = true
        persistPendingDownloads()
    }

    private func cancelledJob(_ id: UUID) {
        downloadTasks.removeValue(forKey: id)
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.status = "Cancelled — partial files kept for resuming"
        job.isCancelled = true
        job.isFinished = true
        persistPendingDownloads()
    }

    private func restorePendingDownloads() {
        guard let data = UserDefaults.standard.data(forKey: pendingDownloadsKey),
              let saved = try? JSONDecoder().decode([PersistedDownloadJob].self, from: data) else { return }
        jobs = saved.map { record in
            let job = DownloadJob(
                id: record.id,
                url: record.url,
                title: record.title,
                cookieSource: BrowserCookies(rawValue: record.cookieSource) ?? .none,
                quality: VideoQuality(rawValue: record.quality) ?? .p1080
            )
            job.progress = record.progress
            if let path = record.partialFolderPath {
                job.partialFolder = URL(fileURLWithPath: path, isDirectory: true)
            }
            job.status = "Interrupted — ready to resume"
            job.isCancelled = true
            job.isFinished = true
            job.needsRepair = record.needsRepair ?? false
            return job
        }
    }

    private func persistPendingDownloads() {
        let pending = jobs.compactMap { job -> PersistedDownloadJob? in
            guard job.folder == nil else { return nil }
            return PersistedDownloadJob(
                id: job.id,
                url: job.url,
                title: job.title,
                progress: job.progress,
                cookieSource: job.cookieSource.rawValue,
                quality: job.quality.rawValue,
                partialFolderPath: job.partialFolder?.path,
                needsRepair: job.needsRepair
            )
        }
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: pendingDownloadsKey)
        }
    }

    private func discoverLegacyIncompleteDownloads() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: libraryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let knownFolders = Set(jobs.compactMap { $0.partialFolder?.standardizedFileURL.path })

        for folder in folders where !knownFolders.contains(folder.standardizedFileURL.path) {
            guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent("presentation.json").path) else { continue }
            let components = folder.lastPathComponent.split(separator: "-", maxSplits: 1).map(String.init)
            guard let slidesLiveID = components.first,
                  !slidesLiveID.isEmpty,
                  slidesLiveID.allSatisfy(\.isNumber) else { continue }

            let readableTitle = components.count > 1
                ? components[1].replacingOccurrences(of: "-", with: " ")
                : "SlidesLive presentation \(slidesLiveID)"
            let job = DownloadJob(
                url: "https://slideslive.com/\(slidesLiveID)",
                title: readableTitle,
                cookieSource: .none,
                quality: .p1080
            )
            job.partialFolder = folder
            job.status = "Interrupted — ready to resume"
            job.isCancelled = true
            job.isFinished = true
            jobs.append(job)
        }
        persistPendingDownloads()
    }

    private func loadItem(at folder: URL) -> LibraryItem? {
        let url = folder.appendingPathComponent("presentation.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(PresentationManifest.self, from: data) else { return nil }
        return LibraryItem(folder: folder, manifest: manifest)
    }

    private func auditCompletedDownloads() async {
        let snapshot = library
        for item in snapshot {
            guard let expected = item.manifest.duration, expected > 0,
                  let videoName = item.manifest.video else { continue }
            let videoURL = item.folder.appendingPathComponent(videoName)
            guard let actual = await TalkDownloader.mediaDuration(at: videoURL),
                  TalkDownloader.isClearlyIncomplete(actual: actual, expected: expected) else { continue }

            library.removeAll { $0.id == item.id }
            if selected?.id == item.id { selected = nil }
            guard !jobs.contains(where: { $0.partialFolder?.standardizedFileURL == item.folder.standardizedFileURL }) else { continue }

            let job = DownloadJob(
                url: item.manifest.source,
                title: item.manifest.title,
                cookieSource: .none,
                quality: .p1080
            )
            job.partialFolder = item.folder
            job.progress = min(0.99, actual / expected)
            job.status = "Video incomplete (\(shortClock(actual)) of about \(shortClock(expected))) — ready to repair"
            job.isCancelled = true
            job.isFinished = true
            job.needsRepair = true
            jobs.insert(job, at: 0)
        }
        persistPendingDownloads()
    }

    private func shortClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
