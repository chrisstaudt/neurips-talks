import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 310, max: 390)
        } detail: {
            Group {
                if model.showingDownloader || model.selected == nil {
                    DownloadView(model: model)
                } else if let selected = model.selected {
                    PlayerView(
                        item: selected,
                        sidebarVisible: columnVisibility != .detailOnly,
                        toggleSidebar: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                            }
                        },
                        enterFullScreen: {
                            columnVisibility = .detailOnly
                            DispatchQueue.main.async {
                                NSApp.keyWindow?.toggleFullScreen(nil)
                            }
                        }
                    )
                        .id(selected.id)
                }
            }
            .frame(minWidth: 720, minHeight: 620)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1040, minHeight: 700)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [.neuripsAccent, .neuripsTeal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "play.rectangle.on.rectangle.fill")
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("NeurIPS Talks").font(.headline)
                        Text("Offline library").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button {
                    model.showingDownloader = true
                    model.selected = nil
                } label: {
                    Label("Download Queue", systemImage: "tray.and.arrow.down.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.neuripsAccent)

                HStack(spacing: 7) {
                    Circle()
                        .fill(sidebarQueueColor)
                        .frame(width: 7, height: 7)
                    Text(sidebarQueueStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 46)

            Divider()

            HStack {
                Text("LIBRARY")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.library.isEmpty {
                    Text("\(model.library.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if model.library.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Color.neuripsAccent.opacity(0.8))
                    Text("No saved talks yet")
                        .font(.headline)
                    Text("Completed downloads will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                List(selection: Binding(
                    get: { model.selected?.id },
                    set: { id in
                        model.selected = model.library.first { $0.id == id }
                        if id != nil { model.showingDownloader = false }
                    }
                )) {
                    ForEach(model.library) { item in
                        let isSelected = model.selected?.id == item.id
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.manifest.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(2)
                            if !item.manifest.conferenceSummary.isEmpty {
                                Text(item.manifest.conferenceSummary)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(isSelected ? selectedSidebarText : Color.neuripsAccent)
                                    .lineLimit(1)
                            }
                            if !item.manifest.displaySpeakers.isEmpty {
                                Label(item.manifest.displaySpeakers, systemImage: "person.2")
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? selectedSidebarText.opacity(0.82) : Color.secondary)
                                    .lineLimit(1)
                            }
                            Label("\(item.manifest.slides.count) slides", systemImage: "rectangle.stack")
                                .font(.caption)
                                .foregroundStyle(isSelected ? selectedSidebarText.opacity(0.82) : Color.secondary)
                        }
                        .padding(.vertical, 5)
                        .tag(Optional(item.id))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                sidebarAction("Choose Library Folder", icon: "folder.badge.gearshape", action: model.chooseLibraryDirectory)
                sidebarAction("Show Library in Finder", icon: "arrow.forward.square", action: model.revealLibrary)
                sidebarAction("Refresh Library", icon: "arrow.clockwise") { model.refreshLibrary() }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var selectedSidebarText: Color {
        Color(nsColor: .selectedControlTextColor)
    }

    private var sidebarQueueStatus: String {
        let active = model.jobs.filter { !$0.isFinished }.count
        let resumable = model.jobs.filter { $0.isCancelled || $0.error != nil }.count
        if active > 0, resumable > 0 { return "\(active) active · \(resumable) ready to resume" }
        if active > 0 { return "\(active) active download\(active == 1 ? "" : "s")" }
        if resumable > 0 { return "\(resumable) ready to resume" }
        return "Queue empty"
    }

    private var sidebarQueueColor: Color {
        if model.jobs.contains(where: { !$0.isFinished }) { return .neuripsAccent }
        if model.jobs.contains(where: { $0.isCancelled || $0.error != nil }) { return .neuripsOrange }
        return .secondary
    }
}
