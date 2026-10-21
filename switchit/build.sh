#!/bin/zsh
# Build SwitchIT.app (Enable/Disable the easyswitch-reconnect agent) into ~/Applications.
# Requires the Xcode Command Line Tools (swiftc). Run install.sh first.
set -e
HERE="${0:A:h}"
APP="${APP_DIR:-$HOME/Applications}/SwitchIT.app"
command -v swiftc >/dev/null || { echo "swiftc not found: run 'xcode-select --install'"; exit 1; }
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macos13" \
  "$HERE/SwitchIT.swift" -o "$APP/Contents/MacOS/SwitchIT"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>SwitchIT</string>
  <key>CFBundleDisplayName</key><string>SwitchIT</string>
  <key>CFBundleExecutable</key><string>SwitchIT</string>
  <key>CFBundleIdentifier</key><string>com.imaginaerum.switchit</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP"
echo "Built $APP"
