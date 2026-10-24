#!/bin/zsh
# easyswitch-reconnect: bring Bluetooth keyboards/mice back to your Mac after
# switching them away (Logitech Easy-Switch, multi-host keyboards, etc.).
#
#   easyswitch-reconnect.sh            manual: reconnect now (resets backoff);
#                                      power-cycle Bluetooth if that fails
#   easyswitch-reconnect.sh --watch    background mode (used by the LaunchAgent):
#                                      rate-limited reconnect attempts, with an
#                                      automatic Bluetooth power cycle as a last
#                                      resort when a recently-connected device
#                                      refuses to come back (see settings below)
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
#   * backs off per device: BASE, 2*BASE, 4*BASE ... up to BACKOFF_MAX.
#
# Why the automatic Bluetooth power cycle: on multi-host Logitech keyboards
# (observed with MX Keys shared between a Mac and an Apple Vision Pro),
# `blueutil --connect` can keep failing after a channel switch because
# bluetoothd is in a stuck state and no amount of retrying with --connect
# recovers it. The only reliable kick is a `blueutil --power 0` / `--power 1`.
# To avoid cycling Bluetooth (and briefly dropping AirPods) for devices that
# are simply out of range, --watch only triggers the cycle when the device
# was connected recently (EASYSWITCH_RECENT_SEEN_WINDOW), and never more
# often than EASYSWITCH_BT_CYCLE_COOLDOWN apart.
#
# Settings (environment variables, set in the LaunchAgent by install.sh):
#   EASYSWITCH_CONNECT_TIMEOUT      max seconds per connect attempt   (default 15)
#   EASYSWITCH_BACKOFF_BASE         first retry delay in seconds      (default 10)
#   EASYSWITCH_BACKOFF_MAX          longest retry delay in seconds    (default 30)
#   EASYSWITCH_AUTO_BT_CYCLE_AFTER  consecutive failed attempts per
#                                   device before --watch triggers an
#                                   automatic Bluetooth power cycle;
#                                   set to 0 to disable                (default 2)
#   EASYSWITCH_BT_CYCLE_COOLDOWN    minimum seconds between automatic
#                                   Bluetooth power cycles             (default 60)
#   EASYSWITCH_RECENT_SEEN_WINDOW   only auto-cycle Bluetooth if the
#                                   device was connected within this
#                                   many seconds (treat as a channel
#                                   switch, not a device that's gone)  (default 900)
zmodload zsh/datetime

CONF="${EASYSWITCH_CONFIG:-$HOME/.config/easyswitch-reconnect/devices}"
STATE="${EASYSWITCH_STATE_DIR:-$HOME/Library/Caches/easyswitch-reconnect}"
BU="${EASYSWITCH_BLUEUTIL:-$(command -v blueutil || echo /opt/homebrew/bin/blueutil)}"
CONNECT_TIMEOUT="${EASYSWITCH_CONNECT_TIMEOUT:-15}"
BACKOFF_BASE="${EASYSWITCH_BACKOFF_BASE:-10}"
BACKOFF_MAX="${EASYSWITCH_BACKOFF_MAX:-30}"
AUTO_BT_CYCLE_AFTER="${EASYSWITCH_AUTO_BT_CYCLE_AFTER:-2}"
BT_CYCLE_COOLDOWN="${EASYSWITCH_BT_CYCLE_COOLDOWN:-60}"
RECENT_SEEN_WINDOW="${EASYSWITCH_RECENT_SEEN_WINDOW:-900}"
BT_CYCLE_OFF_WAIT="${EASYSWITCH_BT_CYCLE_OFF_WAIT:-2}"

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
state_file()    { print -r -- "$STATE/${1//:/-}"; }
lastseen_file() { print -r -- "$STATE/${1//:/-}.lastseen"; }
LAST_CYCLE_FILE="$STATE/last-bt-cycle"

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

# Sets LAST_ATTEMPT to a short description for the log.
try_connect() {
  local start=$EPOCHREALTIME rc
  run_with_timeout "$CONNECT_TIMEOUT" "$BU" --connect $1; rc=$?
  if (( rc == 124 )); then LAST_ATTEMPT="stopped at ${CONNECT_TIMEOUT}s limit"
  else LAST_ATTEMPT="blueutil gave up after $(printf '%.1f' $(( EPOCHREALTIME - start )))s"
  fi
  connected $1
}

# Power-cycle Bluetooth. Honours cooldown so --watch cannot thrash AirPods.
# $1: "force" skips cooldown (used by manual flows).
bt_cycle() {
  local mode="${1:-}" now=${EASYSWITCH_NOW:-$EPOCHSECONDS} last=0
  [[ -r "$LAST_CYCLE_FILE" ]] && last=$(<"$LAST_CYCLE_FILE")
  if [[ "$mode" != "force" ]] && (( now - last < BT_CYCLE_COOLDOWN )); then
    return 1
  fi
  "$BU" --power 0; sleep "$BT_CYCLE_OFF_WAIT"; "$BU" --power 1
  print "$now" > "$LAST_CYCLE_FILE"
  for d in $DEVS; do rm -f "$(state_file $d)"; done
  return 0
}

# Only one instance at a time, so attempts can never pile up.
LOCK="$STATE/lock"
LOCK_OWNED=0
cleanup_lock() { (( LOCK_OWNED )) && rm -rf "$LOCK"; }
# NOTE: the trap must live at script scope. zsh fires `trap … EXIT` on
# *function* exit if the trap is installed inside a function, so an earlier
# `trap 'rm -rf "$LOCK"' EXIT` set inside take_lock() released the lock as
# soon as take_lock returned, letting concurrent manual --watch invocations
# race through the body.
trap cleanup_lock EXIT INT TERM
take_lock() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    local pid; pid="$(<"$LOCK/pid" 2>/dev/null)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then return 1; fi
    rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || return 1   # stale lock
  fi
  print $$ > "$LOCK/pid"
  LOCK_OWNED=1
}

case "$1" in
  --status)
    now=${EASYSWITCH_NOW:-$EPOCHSECONDS}
    for d in $DEVS; do
      sf="$(state_file $d)"; lsf="$(lastseen_file $d)"
      fails=0; next=0; last_seen=0
      [[ -r "$sf" ]] && read fails next < "$sf"
      [[ -r "$lsf" ]] && last_seen=$(<"$lsf")
      seen_note=""
      (( last_seen > 0 )) && seen_note=" (last seen $(( now - last_seen ))s ago)"
      if connected $d; then print "$d connected"
      elif (( next > now )); then print "$d missing, $fails failed attempts, next try in $(( next - now ))s$seen_note"
      else print "$d missing, next try on the next check$seen_note"
      fi
    done
    last_cycle=0; [[ -r "$LAST_CYCLE_FILE" ]] && last_cycle=$(<"$LAST_CYCLE_FILE")
    if (( last_cycle > 0 )); then
      print "last automatic Bluetooth power cycle: $(( now - last_cycle ))s ago"
    fi
    exit 0 ;;

  --bt-cycle)
    bt_cycle force >/dev/null
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
    need_bt_cycle=0
    for d in $DEVS; do
      sf="$(state_file $d)"
      lsf="$(lastseen_file $d)"
      if connected $d; then
        print "$now" > "$lsf"
        [[ -f "$sf" ]] && { rm -f "$sf"; log "$d connected"; }
        continue
      fi
      fails=0; next=0
      [[ -r "$sf" ]] && read fails next < "$sf"
      (( now < next )) && continue              # still backing off
      if try_connect $d; then
        rm -f "$sf"; print "$now" > "$lsf"; log "$d reconnected"
        continue
      fi
      (( fails++ ))
      shift_by=$(( fails > 16 ? 15 : fails - 1 ))
      delay=$(( BACKOFF_BASE << shift_by ))
      (( delay > BACKOFF_MAX )) && delay=$BACKOFF_MAX
      print "$fails $(( now + delay ))" > "$sf"
      (( fails <= 5 )) && log "$d not reachable (attempt $fails, $LAST_ATTEMPT), next try in ${delay}s"
      # Firm fix for the Easy-Switch channel-switch stuck state: when a device
      # was connected to us very recently (i.e. the user just channel-switched
      # back) and plain --connect refuses to work, escalate to a Bluetooth
      # power cycle. Cooldown + recent-seen window keep this from thrashing
      # AirPods for devices that are simply out of range.
      if (( AUTO_BT_CYCLE_AFTER > 0 && fails >= AUTO_BT_CYCLE_AFTER )); then
        last_seen=0
        [[ -r "$lsf" ]] && last_seen=$(<"$lsf")
        if (( last_seen > 0 && now - last_seen <= RECENT_SEEN_WINDOW )); then
          need_bt_cycle=1
        fi
      fi
    done
    if (( need_bt_cycle )); then
      if bt_cycle; then
        log "auto Bluetooth power cycle (recent device stuck after $AUTO_BT_CYCLE_AFTER failed --connect attempts)"
      fi
    fi
    exit 0 ;;

  "")
    take_lock || { echo "Another run is in progress, try again in a few seconds." >&2; exit 1; }
    for d in $DEVS; do rm -f "$(state_file $d)"; done   # manual run resets backoff
    for d in $DEVS; do connected $d || try_connect $d; done
    sleep 2
    for d in $DEVS; do
      if ! connected $d; then
        bt_cycle force >/dev/null
        exit 0
      fi
    done
    exit 0 ;;

  *)
    echo "Unknown option: $1 (use --watch, --status, --refresh, --bt-cycle or no option)" >&2
    exit 2 ;;
esac
