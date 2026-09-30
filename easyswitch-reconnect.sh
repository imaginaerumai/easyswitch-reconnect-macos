#!/bin/zsh
# easyswitch-reconnect: bring Bluetooth keyboards/mice back to your Mac after
# switching them away (Logitech Easy-Switch, multi-host keyboards, etc.).
#
#   easyswitch-reconnect.sh            reconnect; power-cycle Bluetooth if that fails
#   easyswitch-reconnect.sh --watch    soft reconnect only (used by the LaunchAgent)
#   easyswitch-reconnect.sh --refresh  manual: disconnect + reconnect connected devices
#                                      (clears input lag; never run automatically)
CONF="$HOME/.config/easyswitch-reconnect/devices"
BU="$(command -v blueutil || echo /opt/homebrew/bin/blueutil)"
[[ -x "$BU" ]] || { echo "blueutil not found" >&2; exit 1; }
[[ -r "$CONF" ]] || { echo "No config at $CONF - run install.sh" >&2; exit 1; }
DEVS=(${(f)"$(grep -Eo '^[0-9a-fA-F]{2}([-:][0-9a-fA-F]{2}){5}' "$CONF")"})
(( ${#DEVS} )) || exit 0
connected() { [[ "$($BU --is-connected $1)" == 1 ]]; }

if [[ "$1" == --refresh ]]; then
  for d in $DEVS; do
    connected $d || continue
    $BU --disconnect $d >/dev/null 2>&1; sleep 2; $BU --connect $d >/dev/null 2>&1
  done
  exit 0
fi

missing=()
for d in $DEVS; do connected $d || missing+=$d; done
(( ${#missing} == 0 )) && exit 0
for d in $missing; do $BU --connect $d >/dev/null 2>&1; done
[[ "$1" == --watch ]] && exit 0

sleep 2
for d in $DEVS; do
  if ! connected $d; then
    $BU --power 0; sleep 1; $BU --power 1
    exit 0
  fi
done
