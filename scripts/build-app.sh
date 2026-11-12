#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

swift build -c release

APP="$ROOT/dist/ProToolsIndicator.app"
mkdir -p "$APP/Contents/MacOS" "$ROOT/dist/bin"
# Swap binaries atomically: agents may be running the CLI (and the menu bar app may be
# running) while this rebuilds. Copy beside the target, then rename over it, so running
# processes keep their old file and new launches never see a half-written binary.
install_atomic() {
    tmp="$2.new.$$"
    cp "$1" "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$2"
}
install_atomic "$ROOT/.build/release/ProToolsIndicator" "$APP/Contents/MacOS/ProToolsIndicator"
install_atomic "$ROOT/.build/release/pt-indicator" "$ROOT/dist/bin/pt-indicator"

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
