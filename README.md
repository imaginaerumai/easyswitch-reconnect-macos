# easyswitch-reconnect-macos

Automatically reconnects Bluetooth keyboards and mice to your Mac after you switch
them to another device and back. Built for Logitech Easy-Switch devices (MX Keys,
MX Master, etc.) used between a Mac and an Apple Vision Pro, iPad, or another
computer. It should also work with any multi-host Bluetooth keyboard or mouse.

## The problem

You press Easy-Switch to move your keyboard/mouse to another device (e.g. Apple
Vision Pro on channel 2). When you switch back to the Mac (channel 1), the LED
blinks slowly and nothing connects. The only fix is turning Bluetooth off and on
on the Mac.

It looks like macOS doesn't reconnect when the device comes back, so the device
keeps searching. This is our observation, not a documented Apple or Logitech
explanation.

## How it works

- A **LaunchAgent** checks every 5 seconds whether your selected devices are
  connected. That check only asks macOS for the device's current status.
- If a device is missing, it asks macOS to connect to it (`blueutil --connect`),
  but **rate-limited**:
  - each attempt is stopped after 4 seconds,
  - after a failed attempt it waits 10s, then 20s, then at most every 30s,
  - only one copy runs at a time, so attempts can't pile up,
  - as soon as the device is connected again, the backoff resets.
- The background check **never** turns Bluetooth off.
- A **manual command** (bind it to a hotkey) reconnects immediately, resets the
  backoff, and turns Bluetooth off and on if the devices still aren't back after
  2 seconds.

Result: switch back to the Mac and the devices reconnect within about 30 seconds
at most, or instantly with the hotkey.

### Why the rate limiting (audio stutter)

While a keyboard or mouse is on another host, every connect attempt makes the
Mac's Bluetooth radio look for it. The first version retried every 5 seconds
with no time limit on an attempt, and while it ran, the author's AirPods audio
started stuttering. We believe the retries were the cause, but this was not
proven. The current version limits how often and how long it tries.

A second bug made this much worse: `blueutil --is-connected` can return `0` for a
Bluetooth LE device that is connected and working (seen with an MX Master 3,
which still appeared in `blueutil --connected`). Earlier versions relied on
`--is-connected`, so they kept calling `--connect` on devices that were already
connected. The script now treats a device as connected if it appears in
`blueutil --connected` or `--is-connected` says so.

**It has not yet been confirmed that this removes the stutter.** If you hear
audio dropouts, raise the limit (e.g. `BACKOFF_MAX=120 ./install.sh`), or turn
the background check off and use only the hotkey:

```bash
launchctl bootout gui/$(id -u)/com.easyswitch-reconnect
rm ~/Library/LaunchAgents/com.easyswitch-reconnect.plist
```

### Input lag (manual only)

After a Mac-initiated reconnect, input can sometimes lag. Options, safest first:

1. Turn the keyboard/mouse off and on with its power switch.
2. `easyswitch-reconnect.sh --refresh`: disconnects and reconnects the device.
3. `easyswitch-reconnect.sh --bt-cycle`: turns Bluetooth off and on (other
   devices like AirPods drop briefly).

These are deliberately **not** automatic: when an earlier version refreshed the
link on every reconnect, the Mac later could not reconnect or even re-pair the
devices, and recovery required clearing macOS Bluetooth databases. The cause was
not confirmed, but it is not worth the risk.

## Requirements

- macOS with [Homebrew](https://brew.sh)
- [blueutil](https://github.com/toy/blueutil) (the installer installs it)

## Install

```bash
git clone https://github.com/imaginaerumai/easyswitch-reconnect-macos.git
cd easyswitch-reconnect-macos
./install.sh
```

The installer lists your paired Bluetooth devices. Type the numbers of your
keyboard/mouse. They are saved to `~/.config/easyswitch-reconnect/devices`
(one MAC address per line, and you can edit this file later).

Optional settings (pass them to the installer):

| Variable | Default | Meaning |
|---|---|---|
| `INTERVAL` | `5` | seconds between status checks |
| `BACKOFF_MAX` | `30` | longest wait between connect attempts for a missing device |
| `CONNECT_TIMEOUT` | `4` | seconds before a single connect attempt is stopped |

Example: `BACKOFF_MAX=60 ./install.sh`

On first run macOS may ask for Bluetooth permission. Allow it.

## Bind the manual reconnect to a key

> **Note:** the Easy-Switch buttons can't trigger this. Switching channels
> happens inside the keyboard/mouse, and no key press is sent to the Mac. The
> Mac also can't hear from a device that isn't connected. Use your MacBook's
> built-in keyboard (or any key/device that's always connected) instead.
> For most people the background check is enough.

### Option A: Shortcuts app (built in)
1. Open **Shortcuts** and create a new shortcut, e.g. "Reconnect keyboard & mouse".
2. Add the **Run Shell Script** action with:
   ```
   ~/.local/bin/easyswitch-reconnect.sh
   ```
3. Open the shortcut's details (ⓘ) and choose **Add Keyboard Shortcut**, e.g. `⌃⌥⌘K`.
4. Optional: turn on **Pin in Menu Bar** so you can run it with the trackpad.

### Option B: Raycast / Alfred / BetterTouchTool / Hammerspoon
Create a script command or hotkey that runs `~/.local/bin/easyswitch-reconnect.sh`.

## Troubleshooting

- Check the log: `cat /tmp/easyswitch-reconnect.err` (connect attempts and reconnects)
- See devices and backoff: `~/.local/bin/easyswitch-reconnect.sh --status`
- Check the agent is loaded: `launchctl print gui/$(id -u)/com.easyswitch-reconnect`
- See what's connected: `blueutil --connected`
- Input lags after switching back: see [Input lag](#input-lag-manual-only).
- AirPods or other audio stutters: see [Why the rate limiting](#why-the-rate-limiting-audio-stutter).
- If a device never reconnects, remove it in System Settings → Bluetooth
  (Forget), pair it again, and run `./install.sh` again (the address may change).

## Uninstall

```bash
./uninstall.sh
```

## Apple Vision Pro tip

If you use your Mac inside Vision Pro with **Mac Virtual Display**, you may not
need to switch channels at all. With Handoff and "Allow your pointer and
keyboard to move between any nearby Mac or iPad" turned on, the author's Mac
keyboard could type into visionOS apps by looking at them. Whether this works
may depend on your macOS/visionOS versions and keyboard.

## License

MIT
