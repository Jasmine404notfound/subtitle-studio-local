#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$PROJECT_DIR/Sources/SubtitleStudio"
DEST_DIR="$PROJECT_DIR/dist"
BUILD_DIR="${SUBTITLE_BUILD_DIR:-$PROJECT_DIR/.build}"
if [ "$(uname -m)" != arm64 ]; then echo "需要 Apple Silicon Mac（arm64）。" >&2; exit 1; fi
mkdir -p "$DEST_DIR"
mkdir -p "$BUILD_DIR"
# Work around duplicate SwiftBridging module maps in this installed CLT.
# The overlay affects only this build; system files are untouched.
printf '' > "$BUILD_DIR/empty.modulemap"
python3 - "$BUILD_DIR" <<'PYOVERLAY'
import json, pathlib, sys
b = pathlib.Path(sys.argv[1])
source = '/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap'
(b/'overlay.json').write_text(json.dumps({'version':0,'roots':[{'type':'file','name':source,'external-contents':str(b/'empty.modulemap')}]}))
PYOVERLAY
SDK_DIR="$(xcrun --show-sdk-path)"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk ]; then SDK_DIR=/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk; fi
OVERLAY_FLAGS=()
if [ -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk ]; then
  OVERLAY_FLAGS=(-vfsoverlay "$BUILD_DIR/overlay.json" -Xcc -ivfsoverlay -Xcc "$BUILD_DIR/overlay.json")
fi
swiftc -sdk "$SDK_DIR" "${OVERLAY_FLAGS[@]}" -O -swift-version 5 -target arm64-apple-macosx13.0 -module-cache-path "$BUILD_DIR/module-cache" -framework SwiftUI -framework AppKit -framework NaturalLanguage "$SOURCE_DIR/Core.swift" "$SOURCE_DIR/SubtitleProcessing.swift" "$SOURCE_DIR/RecognitionQuality.swift" "$SOURCE_DIR/Vocabulary.swift" "$SOURCE_DIR/CaptionExport.swift" "$SOURCE_DIR/App.swift" "$SOURCE_DIR/SelfTests.swift" -o "$BUILD_DIR/SubtitleStudio"
NAME="字幕转写"
ID="org.subtitle-studio.local"
  APP_DIR="$DEST_DIR/$NAME.app"
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
  cp "$BUILD_DIR/SubtitleStudio" "$APP_DIR/Contents/MacOS/SubtitleStudio"
  cp "$SOURCE_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
  cp "$SOURCE_DIR/Resources/detect_speech.py" "$APP_DIR/Contents/Resources/detect_speech.py"
  cp "$SOURCE_DIR/Resources/proofread.py" "$APP_DIR/Contents/Resources/proofread.py"

  cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SubtitleStudio</string>
<key>CFBundleIdentifier</key><string>$ID</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>10</string>
<key>CFBundleShortVersionString</key><string>1.8</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Subtitle input</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>CFBundleTypeExtensions</key><array><string>srt</string><string>m4a</string><string>mp3</string><string>wav</string><string>mp4</string><string>mov</string><string>flac</string><string>mkv</string></array>
</dict></array>
</dict></plist>
PLIST
  /usr/bin/codesign --force --sign - "$APP_DIR"
"$DEST_DIR/字幕转写.app/Contents/MacOS/SubtitleStudio" --self-test
