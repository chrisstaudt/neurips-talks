import SwiftUI

struct DownloadView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                addDownloadCard
                downloadsSection
            }
            .frame(maxWidth: 900)
            .padding(.horizontal, 42)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [Color.neuripsAccent.opacity(0.10), Color.neuripsTeal.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.neuripsAccent, .neuripsTeal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .shadow(color: Color.neuripsAccent.opacity(0.24), radius: 12, y: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text("Download a talk")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Save the video and synchronized slides for distraction-free offline viewing.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addDownloadCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("PRESENTATION LINK")
                .font(.caption2.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.title3)
                    .foregroundStyle(Color.neuripsAccent)

                TextField("Paste a NeurIPS or SlidesLive URL", text: $model.downloadURL)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($focused)
                    .onSubmit { model.startDownload() }

                Button { model.startDownload() } label: {
                    Label("Add to Queue", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.neuripsAccent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(focused ? Color.neuripsAccent : Color.primary.opacity(0.12), lineWidth: focused ? 2 : 1)
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Access", systemImage: "person.badge.key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Access", selection: $model.cookieSource) {
                        ForEach(BrowserCookies.allCases) { source in Text(source.rawValue).tag(source) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Video quality", systemImage: "sparkles.tv")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Video quality", selection: $model.quality) {
                        ForEach(VideoQuality.allCases) { quality in Text(quality.rawValue).tag(quality) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 130, alignment: .leading)
                }

                Spacer()

                Label("Downloads run in parallel", systemImage: "bolt.horizontal.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.cookieSource != .none {
                Label("Uses your existing browser session. macOS may ask for Keychain or file access.", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Color.neuripsTeal)
            }

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(22)
        .appCard()
    }

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Downloads")
                        .font(.title2.weight(.bold))
                    Text(queueSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.jobs.contains(where: { $0.folder != nil }) {
                    Button("Clear Completed") { model.clearCompletedJobs() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.neuripsAccent)
                }
            }

            if model.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.neuripsAccent)
                    Text("Your queue is ready")
                        .font(.headline)
                    Text("Add one or several presentation links above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .appCard()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.jobs) { job in
                        DownloadJobRow(
                            job: job,
                            watch: { if let folder = job.folder { model.openDownloadedTalk(folder) } },
                            cancel: { model.cancelDownload(job) },
                            resume: { model.resumeDownload(job) },
                            remove: { model.removePartialDownload(job) }
                        )
                    }
                }
            }
        }
    }

    private var queueSummary: String {
        let active = model.jobs.filter { !$0.isFinished }.count
        let paused = model.jobs.filter { $0.isCancelled }.count
        if active > 0 { return "\(active) active" + (paused > 0 ? " · \(paused) ready to resume" : "") }
        if paused > 0 { return "\(paused) ready to resume" }
        return "Completed downloads are also available in your library"
    }
}

private struct DownloadJobRow: View {
    @ObservedObject var job: DownloadJob
    let watch: () -> Void
    let cancel: () -> Void
    let resume: () -> Void
    let remove: () -> Void
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.13))
                    Image(systemName: statusIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(statusLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 16)
                actions
            }

            if !job.isFinished {
                ProgressView(value: job.progress)
                    .tint(Color.neuripsAccent)
            }

            Text(job.error ?? job.status)
                .font(.callout)
                .foregroundStyle(job.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(17)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusColor.opacity(0.18), lineWidth: 1)
        }
        .confirmationDialog(
            "Remove partial download?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Delete Partial Files", role: .destructive, action: remove)
            Button("Keep Download", role: .cancel) {}
        } message: {
            Text("This permanently deletes the downloaded portions of “\(job.title)”.")
        }
    }

    @ViewBuilder private var actions: some View {
        if job.folder != nil {
            Button(action: watch) {
                Label("Watch", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.neuripsTeal)
        } else if !job.isFinished {
            Button(role: .destructive, action: cancel) {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        } else if job.isCancelled || job.error != nil {
            HStack(spacing: 8) {
                Button(action: resume) {
                    Label(job.needsRepair ? "Repair" : "Resume", systemImage: job.needsRepair ? "wrench.and.screwdriver.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.neuripsAccent)

                Button(role: .destructive) {
                    confirmingRemoval = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    private var statusLabel: String {
        if job.needsRepair && job.isFinished { return "Repair needed" }
        if job.isCancelled { return "Ready to resume" }
        if job.error != nil { return "Needs attention" }
        return job.isFinished ? "Ready to watch" : "Downloading"
    }

    private var statusIcon: String {
        if job.needsRepair && job.isFinished { return "wrench.and.screwdriver.fill" }
        if job.isCancelled { return "pause.fill" }
        if job.error != nil { return "exclamationmark" }
        return job.isFinished ? "checkmark" : "arrow.down"
    }

    private var statusColor: Color {
        if job.needsRepair && job.isFinished { return .neuripsOrange }
        if job.isCancelled { return .neuripsOrange }
        if job.error != nil { return .red }
        return job.isFinished ? .neuripsTeal : .neuripsAccent
    }
}
