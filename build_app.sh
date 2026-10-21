#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
TOOLS_DIR="$ROOT_DIR/tools"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/NeurIPS Talks.app"
DOWNLOAD_TOOLS=false
UNIVERSAL=false
ARCHIVE=false

usage() {
  cat <<'EOF'
Usage: ./build_app.sh [options]

  --download-tools  Download the official standalone yt-dlp helper
  --universal       Build for both Apple Silicon and Intel Macs
  --archive         Create a distributable ZIP and SHA-256 checksum
  --help            Show this help
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --download-tools) DOWNLOAD_TOOLS=true ;;
    --universal) UNIVERSAL=true ;;
    --archive) ARCHIVE=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if $DOWNLOAD_TOOLS; then
  mkdir -p "$TOOLS_DIR"
  echo "Downloading official yt-dlp macOS standalone…"
  curl -fL --retry 3 \
    'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos' \
    -o "$TOOLS_DIR/yt-dlp_macos.download"
  chmod +x "$TOOLS_DIR/yt-dlp_macos.download"
  mv "$TOOLS_DIR/yt-dlp_macos.download" "$TOOLS_DIR/yt-dlp_macos"

  YTDLP_VERSION="$("$TOOLS_DIR/yt-dlp_macos" --version)"
  YTDLP_LICENSE_URL="https://raw.githubusercontent.com/yt-dlp/yt-dlp/$YTDLP_VERSION"
  mkdir -p "$TOOLS_DIR/licenses"
  curl -fL --retry 3 "$YTDLP_LICENSE_URL/LICENSE" -o "$TOOLS_DIR/licenses/LICENSE"
  curl -fL --retry 3 "$YTDLP_LICENSE_URL/THIRD_PARTY_LICENSES.txt" -o "$TOOLS_DIR/licenses/THIRD_PARTY_LICENSES.txt"
  /usr/bin/printf '%s\n' "$YTDLP_VERSION" > "$TOOLS_DIR/licenses/VERSION"
fi

BUILD_ARGUMENTS=(-c release)
if $UNIVERSAL; then
  BUILD_ARGUMENTS+=(--arch arm64 --arch x86_64)
fi

echo "Building native app…"
swift build "${BUILD_ARGUMENTS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Tools" "$APP_DIR/Contents/Resources/Licenses/yt-dlp"
cp "$BIN_DIR/NeurIPSTalks" "$APP_DIR/Contents/MacOS/NeurIPSTalks"
cp "$ROOT_DIR/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/AppResources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/LICENSE" "$APP_DIR/Contents/Resources/Licenses/NeurIPS-Talks-MIT.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"

VERSION="${APP_VERSION:-}"
VERSION="${VERSION#v}"
if [[ -n "$VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" "$APP_DIR/Contents/Info.plist"
fi

if [[ -f "$TOOLS_DIR/yt-dlp_macos" ]]; then
  cp "$TOOLS_DIR/yt-dlp_macos" "$APP_DIR/Contents/Resources/Tools/yt-dlp"
  chmod +x "$APP_DIR/Contents/Resources/Tools/yt-dlp"
  if [[ -f "$TOOLS_DIR/licenses/LICENSE" && -f "$TOOLS_DIR/licenses/THIRD_PARTY_LICENSES.txt" ]]; then
    cp "$TOOLS_DIR/licenses/LICENSE" "$APP_DIR/Contents/Resources/Licenses/yt-dlp/LICENSE"
    cp "$TOOLS_DIR/licenses/THIRD_PARTY_LICENSES.txt" "$APP_DIR/Contents/Resources/Licenses/yt-dlp/THIRD_PARTY_LICENSES.txt"
    if [[ -f "$TOOLS_DIR/licenses/VERSION" ]]; then
      cp "$TOOLS_DIR/licenses/VERSION" "$APP_DIR/Contents/Resources/Licenses/yt-dlp/VERSION"
    fi
  else
    echo "Warning: yt-dlp license files are missing. Run with --download-tools before distributing the app."
  fi
else
  echo "Warning: app built without yt-dlp. Run with --download-tools to bundle it."
fi

/usr/bin/xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
du -sh "$APP_DIR"

if $ARCHIVE; then
  ARCHIVE_PATH="$DIST_DIR/NeurIPS-Talks-macOS-universal.zip"
  CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
  rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"
  (cd "$DIST_DIR" && /usr/bin/shasum -a 256 "${ARCHIVE_PATH:t}" > "${CHECKSUM_PATH:t}")
  echo "Archived: $ARCHIVE_PATH"
fi
