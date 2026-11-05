#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

swift build -c release

APP="$ROOT/dist/ProToolsIndicator.app"
mkdir -p "$APP/Contents/MacOS" "$ROOT/dist/bin"
cp "$ROOT/.build/release/ProToolsIndicator" "$APP/Contents/MacOS/ProToolsIndicator"
cp "$ROOT/.build/release/pt-indicator" "$ROOT/dist/bin/pt-indicator"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>ProToolsIndicator</string>
	<key>CFBundleIdentifier</key>
	<string>com.takeoneaudio.protoolsindicator</string>
	<key>CFBundleName</key>
	<string>Pro Tools Indicator</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

printf 'Built %s\n' "$APP"
printf 'CLI: %s\n' "$ROOT/dist/bin/pt-indicator"
