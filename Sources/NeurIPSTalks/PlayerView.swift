import AVKit
import SwiftUI

private enum PlayerLayout: String, CaseIterable, Identifiable {
    case split = "Split"
    case slides = "Slides"
    case overlay = "Overlay"
    var id: String { rawValue }
}

private enum FloatingVideoSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    var id: String { rawValue }

    var widthFraction: CGFloat {
        switch self {
        case .small: 0.25
        case .medium: 0.34
        case .large: 0.44
        }
    }
}

struct PlayerView: View {
    let item: LibraryItem
    let sidebarVisible: Bool
    let toggleSidebar: () -> Void
    let enterFullScreen: () -> Void

    @State private var player: AVPlayer?
    @State private var activeSlide = 0
    @State private var timeObserver: Any?
    @State private var isPlaying = false
    @State private var layout: PlayerLayout = .split
    @State private var showTimeline = true
    @State private var floatingVideoSize: FloatingVideoSize = .medium
    @State private var overlayCenter: CGPoint?
    @State private var dragStartCenter: CGPoint?

    private var slide: Slide? {
        guard item.manifest.slides.indices.contains(activeSlide) else { return nil }
        return item.manifest.slides[activeSlide]
    }

    var body: some View {
        VStack(spacing: 0) {
            playerHeader

            playbackCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)

            playbackControls
                .padding(.horizontal, 18)
                .padding(.vertical, 11)

            if showTimeline {
                timeline
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: preparePlayer)
        .onDisappear(perform: releasePlayer)
        .onChange(of: item.id) { _, _ in
            releasePlayer()
            activeSlide = 0
            overlayCenter = nil
            preparePlayer()
        }
        .onChange(of: floatingVideoSize) { _, _ in overlayCenter = nil }
    }

    private var playerHeader: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(item.manifest.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                if !item.manifest.displaySpeakers.isEmpty {
                    Label(item.manifest.displaySpeakers, systemImage: "person.2.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if !item.manifest.conferenceSummary.isEmpty {
                        metadataBadge(item.manifest.conferenceSummary, icon: "building.columns")
                    }
                    if let location = item.manifest.details?.location {
                        metadataBadge(location, icon: "mappin.and.ellipse")
                    }
                    metadataBadge("\(item.manifest.slides.count) slides" + durationText, icon: "rectangle.stack")
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                Picker("Layout", selection: $layout) {
                    ForEach(PlayerLayout.allCases) { option in Text(option.rawValue).tag(option) }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)

                HStack(spacing: 8) {
                    if layout == .overlay {
                        Picker("Video Size", selection: $floatingVideoSize) {
                            ForEach(FloatingVideoSize.allCases) { size in Text(size.rawValue).tag(size) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showTimeline.toggle() }
                    } label: {
                        Label(showTimeline ? "Hide Timeline" : "Show Timeline", systemImage: "rectangle.stack.badge.play")
                    }

                    Button(action: toggleSidebar) {
                        Label(sidebarVisible ? "Hide Library" : "Show Library", systemImage: "sidebar.left")
                    }

                    Button(action: enterFullScreen) {
                        Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 42)
        .padding(.bottom, 16)
    }

    @ViewBuilder private var playbackCanvas: some View {
        switch layout {
        case .split:
            HSplitView {
                slideCanvas.frame(minWidth: 330)
                videoCanvas.frame(minWidth: 280)
            }
        case .slides:
            slideCanvas
        case .overlay:
            GeometryReader { geometry in
                ZStack {
                    slideCanvas
                    if player != nil {
                        floatingVideo(in: geometry.size)
                    }
                }
            }
        }
    }

    private var slideCanvas: some View {
        ZStack {
            Color.black
            if let slide, let image = NSImage(contentsOf: item.folder.appendingPathComponent(slide.src)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                ContentUnavailableView("Slide unavailable", systemImage: "rectangle.slash")
                    .foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var videoCanvas: some View {
        ZStack {
            Color.black
            if let player { NativeVideoPlayer(player: player) }
            else { ContentUnavailableView("Video unavailable", systemImage: "video.slash") }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func floatingVideo(in bounds: CGSize) -> some View {
        let panelSize = floatingPanelSize(in: bounds)
        let defaultPosition = CGPoint(
            x: bounds.width - panelSize.width / 2 - 18,
            y: bounds.height - panelSize.height / 2 - 18
        )
        let position = clamped(overlayCenter ?? defaultPosition, panel: panelSize, in: bounds)

        return VStack(spacing: 0) {
            HStack(spacing: 7) {
                Label("Speaker video", systemImage: "video.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.regularMaterial)
            .contentShape(Rectangle())
            .gesture(dragGesture(panel: panelSize, in: bounds, defaultPosition: defaultPosition))

            if let player { NativeVideoPlayer(player: player) }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, y: 7)
        .position(position)
        .onAppear {
            if overlayCenter == nil { overlayCenter = defaultPosition }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(.neuripsAccent)
            .keyboardShortcut(.space, modifiers: [])

            Button { select(activeSlide - 1) } label: {
                Label("Previous Slide", systemImage: "chevron.left")
            }
            .disabled(activeSlide == 0)

            Text("Slide \(activeSlide + 1) of \(item.manifest.slides.count)")
                .font(.callout.weight(.medium))
                .monospacedDigit()

            Button { select(activeSlide + 1) } label: {
                Label("Next Slide", systemImage: "chevron.right")
            }
            .disabled(activeSlide + 1 >= item.manifest.slides.count)

            Spacer()

            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.folder])
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SLIDE TIMELINE")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(item.manifest.slides.enumerated()), id: \.element.id) { index, slide in
                        Button { select(index) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                if let image = NSImage(contentsOf: item.folder.appendingPathComponent(slide.src)) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 132, height: 74)
                                        .background(.black)
                                }
                                HStack {
                                    Text("Slide \(slide.number)").bold()
                                    Spacer()
                                    Text(clock(slide.start)).monospacedDigit()
                                }
                                .font(.caption2)
                            }
                            .padding(5)
                            .frame(width: 144)
                            .background(activeSlide == index ? Color.neuripsAccent.opacity(0.18) : Color.secondary.opacity(0.07))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(activeSlide == index ? Color.neuripsAccent : Color.secondary.opacity(0.18))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private var durationText: String {
        guard let duration = item.manifest.duration else { return "" }
        return " · \(clock(duration))"
    }

    private func metadataBadge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.10), in: Capsule())
    }

    private func preparePlayer() {
        guard let name = item.manifest.video else { return }
        let newPlayer = AVPlayer(url: item.folder.appendingPathComponent(name))
        player = newPlayer
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = time.seconds
            activeSlide = item.manifest.slides.lastIndex { $0.start <= seconds + 0.05 } ?? 0
            isPlaying = newPlayer.timeControlStatus == .playing
        }
    }

    private func releasePlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func select(_ index: Int) {
        guard item.manifest.slides.indices.contains(index) else { return }
        activeSlide = index
        player?.seek(
            to: CMTime(seconds: item.manifest.slides[index].start, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func floatingPanelSize(in bounds: CGSize) -> CGSize {
        let width = min(max(220, bounds.width * floatingVideoSize.widthFraction), bounds.width - 36)
        return CGSize(width: width, height: width * 9 / 16 + 34)
    }

    private func clamped(_ point: CGPoint, panel: CGSize, in bounds: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, panel.width / 2 + 10), bounds.width - panel.width / 2 - 10),
            y: min(max(point.y, panel.height / 2 + 10), bounds.height - panel.height / 2 - 10)
        )
    }

    private func dragGesture(panel: CGSize, in bounds: CGSize, defaultPosition: CGPoint) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartCenter == nil { dragStartCenter = overlayCenter ?? defaultPosition }
                guard let start = dragStartCenter else { return }
                overlayCenter = clamped(
                    CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height),
                    panel: panel,
                    in: bounds
                )
            }
            .onEnded { _ in dragStartCenter = nil }
    }

    private func clock(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
