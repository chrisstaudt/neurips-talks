# NeurIPS Talks

A small native macOS app for downloading and watching NeurIPS presentations that use SlidesLive. It keeps the presenter video, original slides, and slide timings together for synchronized offline playback.

This is an unofficial community project and is not affiliated with or endorsed by NeurIPS or SlidesLive.

> Download only presentations you are authorized to access and save. The app does not bypass DRM or access controls.

## Features

- Paste a NeurIPS presentation page or direct SlidesLive URL
- Download several talks concurrently
- Stop, resume, repair, and remove partial downloads
- Reuse already-downloaded slides when repairing a video
- Use an existing Chrome, Safari, or Firefox login for authorized restricted pages
- Keep video and slides synchronized during offline playback
- Jump to a slide by selecting it in the timeline
- Split, slide-only, and movable picture-in-picture layouts
- Adjustable panes, focused playback, and full screen
- Store speaker, conference, year, event type, and location metadata when available
- Detect truncated video files instead of incorrectly marking them complete

## Install

Download `NeurIPS-Talks-macOS-universal.zip` from the [latest release](../../releases/latest), unzip it, and move **NeurIPS Talks.app** to Applications.

Release builds are ad-hoc signed unless the repository owner configures Apple Developer signing and notarization. On first launch, you may need to Control-click the app, choose **Open**, and confirm. Alternatively, use **System Settings → Privacy & Security → Open Anyway**.

The release supports Apple Silicon and Intel Macs running macOS 14 or newer.

## Usage

1. Open **Download Queue**.
2. Paste a NeurIPS presentation page or direct SlidesLive URL.
3. Select **Public page**, or choose a browser login for a page you are authorized to access.
4. Choose the preferred maximum video quality and select **Add to Queue**.
5. Select **Watch** when the download finishes.

Downloads are stored in `~/Movies/NeurIPS Talks` by default. You can choose another library folder from the sidebar.

If the app or computer stops during a download, partial media and slides remain in the queue. The app also compares downloaded media duration with SlidesLive metadata and offers **Repair** when a supposedly completed video is truncated.

## Build from source

Requirements:

- macOS 14 or newer
- Xcode 16 or newer, or compatible Xcode Command Line Tools
- Internet access when downloading the `yt-dlp` helper

No Homebrew packages, Python environment, ffmpeg installation, or third-party Swift packages are required.

After cloning the repository, run `./build_app.sh --download-tools` from its root.

The app is written to `dist/NeurIPS Talks.app`.

Build a universal app and distributable ZIP:

```bash
./build_app.sh --download-tools --universal --archive
```

Run the test suite with `swift test`.

## Publishing a release

The release workflow builds a universal app, bundles the official standalone `yt-dlp` helper, ad-hoc signs the bundle, creates a ZIP and SHA-256 checksum, and uploads both to a GitHub Release.

```bash
git tag v1.0.0
git push origin v1.0.0
```

The regular CI workflow builds and tests every pull request and push to `main`. For warning-free distribution outside a small trusted group, replace ad-hoc signing with a Developer ID Application certificate and Apple notarization.

## Privacy and access

Talks remain in the library folder on your Mac. The app contacts the supplied NeurIPS or SlidesLive page and the media hosts referenced by it. If browser access is selected, the bundled downloader reads the relevant local browser session; macOS may request Keychain or file access. Browser cookies are not copied into the talk library or application preferences.

## Third-party software

NeurIPS Talks invokes [yt-dlp](https://github.com/yt-dlp/yt-dlp) as a separate executable to read presentation metadata and download media. Release builds bundle the official universal `yt-dlp_macos` executable so users do not need to install it separately.

The yt-dlp source is offered under the Unlicense. The official PyInstaller-based macOS executable also contains components under GPLv3+ and other licenses; the upstream project describes the combined release executable as GPLv3+. Its exact upstream license and third-party notices are downloaded alongside the executable and included in the app under `Contents/Resources/Licenses`.

The MIT license in this repository applies to the NeurIPS Talks source code, not to bundled third-party software. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

## Project structure

- `Sources/NeurIPSTalks` — SwiftUI application, downloader, and native player
- `AppResources` — application metadata and icon artwork
- `Tests/NeurIPSTalksTests` — Swift tests
- `build_app.sh` — local and CI packaging script
- `.github/workflows` — build and release automation

## License

[MIT](LICENSE)
