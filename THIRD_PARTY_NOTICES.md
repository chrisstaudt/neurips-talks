# Third-party notices

## yt-dlp

NeurIPS Talks invokes the official `yt-dlp_macos` executable as a separate process for metadata extraction and media downloading.

- Project: [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- Upstream releases and corresponding source: <https://github.com/yt-dlp/yt-dlp/releases>
- Upstream license information: <https://github.com/yt-dlp/yt-dlp#licensing>

The yt-dlp source is offered under the Unlicense. According to the upstream licensing documentation, the official PyInstaller-bundled executables contain GPLv3+ and other third-party components, and the combined executable is distributed under GPLv3+.

When `build_app.sh --download-tools` downloads a yt-dlp release, it also downloads that exact release tag's `LICENSE` and `THIRD_PARTY_LICENSES.txt`. The packaging step places these files in:

```text
NeurIPS Talks.app/Contents/Resources/Licenses/yt-dlp/
```

Those files govern the bundled executable. The repository's MIT license applies only to the NeurIPS Talks source code and does not replace any third-party license.

NeurIPS and SlidesLive names and marks belong to their respective owners. This project is unofficial and is not affiliated with or endorsed by either organization.
