#!/bin/zsh
# easyswitch-reconnect: bring Bluetooth keyboards/mice back to your Mac after
# switching them away (Logitech Easy-Switch, multi-host keyboards, etc.).
#
#   easyswitch-reconnect.sh           reconnect; power-cycle Bluetooth if that fails
#   easyswitch-reconnect.sh --watch   soft reconnect only (used by the LaunchAgent)
CONF="$HOME/.config/easyswitch-reconnect/devices"
BU="$(command -v blueutil || echo /opt/homebrew/bin/blueutil)"
[[ -x "$BU" ]] || { echo "blueutil not found" >&2; exit 1; }
[[ -r "$CONF" ]] || { echo "No config at $CONF - run install.sh" >&2; exit 1; }
DEVS=(${(f)"$(grep -Eo '^[0-9a-fA-F]{2}([-:][0-9a-fA-F]{2}){5}' "$CONF")"})
(( ${#DEVS} )) || exit 0

missing=()
for d in $DEVS; do [[ "$($BU --is-connected $d)" == 1 ]] || missing+=$d; done
(( ${#missing} == 0 )) && exit 0
for d in $missing; do $BU --connect $d >/dev/null 2>&1; done
[[ "$1" == --watch ]] && exit 0

sleep 2
for d in $DEVS; do
  if [[ "$($BU --is-connected $d)" != 1 ]]; then
    $BU --power 0; sleep 1; $BU --power 1
    exit 0
  fi
done
