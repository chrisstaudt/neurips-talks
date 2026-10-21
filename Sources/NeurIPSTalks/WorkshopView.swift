import SwiftUI

struct WorkshopView: View {
    let item: LibraryItem
    @ObservedObject var model: AppModel
    let sidebarVisible: Bool
    let toggleSidebar: () -> Void
    let enterFullScreen: () -> Void

    @State private var selectedSegments: Set<String> = []
    @State private var playingTalk: LibraryItem?

    private var workshop: WorkshopManifest { item.workshop! }
    private var recordedSegments: [WorkshopSegment] { workshop.schedule.filter(\.hasVideo) }
    private var selectableSegments: [WorkshopSegment] {
        recordedSegments.filter { item.downloadedTalk(for: $0) == nil && model.queuedJob(for: $0) == nil }
    }

    var body: some View {
        Group {
            if let playingTalk {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            self.playingTalk = nil
                        } label: {
                            Label("Workshop Recordings", systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.neuripsAccent)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 32)
                    .padding(.bottom, 4)
                    .zIndex(1)

                    PlayerView(
                        item: playingTalk,
                        sidebarVisible: sidebarVisible,
                        toggleSidebar: toggleSidebar,
                        enterFullScreen: enterFullScreen,
                        topPadding: 12
                    )
                    .id(playingTalk.id)
                }
            } else {
                scheduleView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var scheduleView: some View {
        VStack(spacing: 0) {
            workshopHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(recordedSegments) { segment in
                        scheduleRow(segment)
                    }
                }
                .padding(18)
                .padding(.bottom, selectedSegments.isEmpty ? 0 : 70)
            }
            .overlay(alignment: .bottom) {
                if !selectedSegments.isEmpty {
                    downloadBar
                        .padding(18)
                }
            }
        }
    }

    private var workshopHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(workshop.title)
                        .font(.largeTitle.weight(.bold))
                    Text(workshopSummary)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.neuripsAccent)
                    if !workshop.organizers.isEmpty {
                        Label(workshop.organizers, systemImage: "person.3.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 20)
                VStack(alignment: .trailing, spacing: 9) {
                    Button(action: toggleSidebar) {
                        Label(sidebarVisible ? "Hide Library" : "Show Library", systemImage: "sidebar.left")
                    }
                    if !selectableSegments.isEmpty {
                        Button("Select All Recordings") {
                            selectedSegments = Set(selectableSegments.map(\.id))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.neuripsAccent)
                    }
                }
            }

            if !workshop.abstract.isEmpty {
                Text(workshop.abstract)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            HStack(spacing: 10) {
                Label("\(recordedSegments.count) recorded sessions", systemImage: "video.fill")
                if !item.workshopTalks.isEmpty {
                    Label("\(item.workshopTalks.count) downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.neuripsTeal)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 42)
        .padding(.bottom, 18)
    }

    private func scheduleRow(_ segment: WorkshopSegment) -> some View {
        let downloaded = item.downloadedTalk(for: segment)
        let queued = model.queuedJob(for: segment)
        let canSelect = segment.hasVideo && downloaded == nil && queued == nil

        return HStack(alignment: .top, spacing: 14) {
            if canSelect {
                Toggle("Select \(segment.title)", isOn: selectionBinding(for: segment.id))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
            } else {
                Image(systemName: statusIcon(downloaded: downloaded, queued: queued, hasVideo: segment.hasVideo))
                    .frame(width: 16)
                    .foregroundStyle(statusColor(downloaded: downloaded, queued: queued, hasVideo: segment.hasVideo))
                    .padding(.top, 3)
            }

            Text(segment.time)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(segment.title)
                    .font(.headline)
                if let abstract = segment.abstract, !abstract.isEmpty {
                    Text(abstract)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text(statusText(downloaded: downloaded, queued: queued, hasVideo: segment.hasVideo))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor(downloaded: downloaded, queued: queued, hasVideo: segment.hasVideo))
            }

            Spacer(minLength: 12)

            if let downloaded {
                Button {
                    playingTalk = downloaded
                } label: {
                    Label("Watch", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.neuripsTeal)
            } else if queued != nil {
                Button("View Queue") {
                    model.showingDownloader = true
                    model.selected = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var downloadBar: some View {
        HStack(spacing: 14) {
            Text("\(selectedSegments.count) recording\(selectedSegments.count == 1 ? "" : "s") selected")
                .font(.callout.weight(.semibold))
            Spacer()
            Button("Clear") { selectedSegments.removeAll() }
                .buttonStyle(.borderless)
            Button {
                let selected = recordedSegments.filter { selectedSegments.contains($0.id) }
                model.downloadWorkshopSegments(selected, into: item)
                selectedSegments.removeAll()
                model.showingDownloader = true
                model.selected = nil
            } label: {
                Label("Download Selected", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.neuripsAccent)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedSegments.contains(id) },
            set: { selected in
                if selected { selectedSegments.insert(id) }
                else { selectedSegments.remove(id) }
            }
        )
    }

    private var workshopSummary: String {
        var parts = [workshop.conference]
        if let year = workshop.year { parts[0] += " \(year)" }
        parts.append("Workshop")
        if let location = workshop.location { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private func statusText(downloaded: LibraryItem?, queued: DownloadJob?, hasVideo: Bool) -> String {
        if downloaded != nil { return "Downloaded" }
        if let queued {
            if queued.error != nil || queued.isCancelled { return "Needs attention in Download Queue" }
            return queued.isFinished ? "Ready in Download Queue" : "In Download Queue"
        }
        return hasVideo ? "Recording available" : "No separate recording"
    }

    private func statusIcon(downloaded: LibraryItem?, queued: DownloadJob?, hasVideo: Bool) -> String {
        if downloaded != nil { return "checkmark.circle.fill" }
        if queued != nil { return "arrow.down.circle.fill" }
        return hasVideo ? "video.fill" : "minus.circle"
    }

    private func statusColor(downloaded: LibraryItem?, queued: DownloadJob?, hasVideo: Bool) -> Color {
        if downloaded != nil { return .neuripsTeal }
        if queued != nil { return .neuripsAccent }
        return hasVideo ? .neuripsAccent : .secondary
    }
}
