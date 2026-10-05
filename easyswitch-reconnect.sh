#!/bin/zsh
# easyswitch-reconnect: bring Bluetooth keyboards/mice back to your Mac after
# switching them away (Logitech Easy-Switch, multi-host keyboards, etc.).
#
#   easyswitch-reconnect.sh            manual: reconnect now (resets backoff);
#                                      power-cycle Bluetooth if that fails
#   easyswitch-reconnect.sh --watch    background mode (used by the LaunchAgent):
#                                      rate-limited reconnect attempts, never
#                                      touches Bluetooth power
#   easyswitch-reconnect.sh --status   show devices and backoff state
#   easyswitch-reconnect.sh --refresh  manual: disconnect + reconnect connected
#                                      devices (may clear input lag)
#   easyswitch-reconnect.sh --bt-cycle manual: turn Bluetooth off and on
#
# Why the rate limiting: while a device is on another host, every connect
# attempt keeps the Mac's Bluetooth radio busy looking for it. Retrying every
# few seconds (and letting a single attempt hang) can interfere with other
# Bluetooth traffic such as AirPods audio. --watch therefore:
#   * runs one instance at a time (lock),
#   * caps each connect attempt at EASYSWITCH_CONNECT_TIMEOUT seconds,
#   * backs off per device: 10s, 20s, 40s ... up to EASYSWITCH_BACKOFF_MAX.
#
# Settings (environment variables, set in the LaunchAgent by install.sh):
#   EASYSWITCH_CONNECT_TIMEOUT  max seconds per connect attempt   (default 4)
#   EASYSWITCH_BACKOFF_BASE     first retry delay in seconds      (default 10)
#   EASYSWITCH_BACKOFF_MAX      longest retry delay in seconds    (default 30)
zmodload zsh/datetime

CONF="${EASYSWITCH_CONFIG:-$HOME/.config/easyswitch-reconnect/devices}"
STATE="${EASYSWITCH_STATE_DIR:-$HOME/Library/Caches/easyswitch-reconnect}"
BU="${EASYSWITCH_BLUEUTIL:-$(command -v blueutil || echo /opt/homebrew/bin/blueutil)}"
CONNECT_TIMEOUT="${EASYSWITCH_CONNECT_TIMEOUT:-4}"
BACKOFF_BASE="${EASYSWITCH_BACKOFF_BASE:-10}"
BACKOFF_MAX="${EASYSWITCH_BACKOFF_MAX:-30}"

[[ -x "$BU" ]] || { echo "blueutil not found" >&2; exit 1; }
[[ -r "$CONF" ]] || { echo "No config at $CONF - run install.sh" >&2; exit 1; }
DEVS=(${(f)"$(grep -Eo '^[0-9a-fA-F]{2}([-:][0-9a-fA-F]{2}){5}' "$CONF")"})
(( ${#DEVS} )) || exit 0
mkdir -p "$STATE"

log() { print -r -- "$(strftime '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS) $*" >&2; }
# A device counts as connected if it is in `blueutil --connected` OR
# `--is-connected` says so. `--is-connected` alone is not reliable: for some
# Bluetooth LE devices (seen with an MX Master 3) it returns 0 while the device
# is connected and working, which made earlier versions keep calling --connect
# on a device that was already connected.
connected() {
  local addr="${${(L)1}//:/-}"
  "$BU" --connected 2>/dev/null | grep -qi "^address: $addr," && return 0
  [[ "$("$BU" --is-connected $1 2>/dev/null)" == 1 ]]
}
state_file() { print -r -- "$STATE/${1//:/-}"; }

# Run a command, killing it if it takes longer than $1 seconds.
run_with_timeout() {
  local limit=$1; shift
  "$@" >/dev/null 2>&1 &
  local pid=$! ticks=0
  while kill -0 $pid 2>/dev/null; do
    if (( ticks >= limit * 10 )); then
      kill $pid 2>/dev/null; sleep 0.2; kill -9 $pid 2>/dev/null
      wait $pid 2>/dev/null
      return 124
    fi
    sleep 0.1; (( ticks++ ))
  done
  wait $pid 2>/dev/null
}

try_connect() { run_with_timeout "$CONNECT_TIMEOUT" "$BU" --connect $1; connected $1; }

# Only one instance at a time, so attempts can never pile up.
LOCK="$STATE/lock"
take_lock() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    local pid; pid="$(<"$LOCK/pid" 2>/dev/null)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then return 1; fi
    rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || return 1   # stale lock
  fi
  print $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT
}

case "$1" in
  --status)
    now=${EASYSWITCH_NOW:-$EPOCHSECONDS}
    for d in $DEVS; do
      sf="$(state_file $d)"; fails=0; next=0
      [[ -r "$sf" ]] && read fails next < "$sf"
      if connected $d; then print "$d connected"
      elif (( next > now )); then print "$d missing, $fails failed attempts, next try in $(( next - now ))s"
      else print "$d missing, next try on the next check"
      fi
    done
    exit 0 ;;

  --bt-cycle)
    "$BU" --power 0; sleep 2; "$BU" --power 1
    exit 0 ;;

  --refresh)
    take_lock || { echo "Another run is in progress, try again in a few seconds." >&2; exit 1; }
    for d in $DEVS; do
      connected $d || continue
      run_with_timeout "$CONNECT_TIMEOUT" "$BU" --disconnect $d
      sleep 2
      try_connect $d
    done
    exit 0 ;;

  --watch)
    take_lock || exit 0
    now=${EASYSWITCH_NOW:-$EPOCHSECONDS}
    for d in $DEVS; do
      sf="$(state_file $d)"
      if connected $d; then
        [[ -f "$sf" ]] && { rm -f "$sf"; log "$d connected"; }
        continue
      fi
      fails=0; next=0
      [[ -r "$sf" ]] && read fails next < "$sf"
      (( now < next )) && continue              # still backing off
      if try_connect $d; then
        rm -f "$sf"; log "$d reconnected"
        continue
      fi
      (( fails++ ))
      shift_by=$(( fails > 16 ? 15 : fails - 1 ))
      delay=$(( BACKOFF_BASE << shift_by ))
      (( delay > BACKOFF_MAX )) && delay=$BACKOFF_MAX
      print "$fails $(( now + delay ))" > "$sf"
      (( fails <= 5 )) && log "$d not reachable (attempt $fails), next try in ${delay}s"
    done
    exit 0 ;;

  "")
    take_lock || { echo "Another run is in progress, try again in a few seconds." >&2; exit 1; }
    for d in $DEVS; do rm -f "$(state_file $d)"; done   # manual run resets backoff
    for d in $DEVS; do connected $d || try_connect $d; done
    sleep 2
    for d in $DEVS; do
      if ! connected $d; then
        "$BU" --power 0; sleep 1; "$BU" --power 1
        exit 0
      fi
    done
    exit 0 ;;

  *)
    echo "Unknown option: $1 (use --watch, --status, --refresh, --bt-cycle or no option)" >&2
    exit 2 ;;
esac
