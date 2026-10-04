#!/bin/zsh
LABEL=com.easyswitch-reconnect
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/easyswitch-reconnect.sh"
rm -rf "$HOME/.config/easyswitch-reconnect" "$HOME/Library/Caches/easyswitch-reconnect"
rm -f /tmp/easyswitch-reconnect.err
echo "Uninstalled. (blueutil left installed: 'brew uninstall blueutil' to remove.)"
