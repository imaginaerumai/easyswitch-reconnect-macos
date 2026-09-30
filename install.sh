#!/bin/zsh
# Installer for easyswitch-reconnect (macOS).
set -e
LABEL=com.easyswitch-reconnect
BIN="$HOME/.local/bin/easyswitch-reconnect.sh"
CONF_DIR="$HOME/.config/easyswitch-reconnect"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INTERVAL="${INTERVAL:-5}"
HERE="${0:A:h}"

command -v brew >/dev/null || { echo "Homebrew is required: https://brew.sh"; exit 1; }
command -v blueutil >/dev/null || brew install blueutil
BU="$(command -v blueutil)"

echo "Paired Bluetooth devices:"
lines=("${(@f)$($BU --paired)}")
i=1
for l in $lines; do
  name="${l##*name: \"}"; name="${name%%\"*}"
  addr="${${l#address: }%%,*}"
  printf "  %2d) %s  [%s]\n" $i "$name" "$addr"; ((i++))
done
echo
read "sel?Numbers of the devices to keep connected (space-separated, e.g. '3 6'): "
mkdir -p "$CONF_DIR"
: > "$CONF_DIR/devices"
for n in ${=sel}; do
  l="${lines[$n]}"; [[ -n "$l" ]] || { echo "Skipping invalid choice: $n"; continue; }
  name="${l##*name: \"}"; name="${name%%\"*}"
  echo "${${l#address: }%%,*}  # $name" >> "$CONF_DIR/devices"
done
[[ -s "$CONF_DIR/devices" ]] || { echo "No devices selected, aborting."; exit 1; }
echo "Saved to $CONF_DIR/devices:"; cat "$CONF_DIR/devices"

mkdir -p "${BIN:h}" "${PLIST:h}"
install -m 755 "$HERE/easyswitch-reconnect.sh" "$BIN"

cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string><string>--watch</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>StandardErrorPath</key><string>/tmp/easyswitch-reconnect.err</string>
</dict></plist>
PL

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo
echo "Installed. Background check runs every ${INTERVAL}s."
echo "Manual reconnect (with Bluetooth reset fallback): $BIN"
echo "See README for binding it to a hotkey."
