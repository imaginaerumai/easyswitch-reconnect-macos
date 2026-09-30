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

- A **LaunchAgent** runs every 5 seconds. If a selected device isn't connected,
  it asks macOS to connect to it (`blueutil --connect`). It **never** turns
  Bluetooth off, so your other devices (AirPods etc.) aren't affected. While the
  device is on another host, the attempt just fails quietly.
- A **manual command** does the same and, if the devices still aren't back after
  2 seconds, turns Bluetooth off and on. You can bind it to a hotkey.

- **Input lag (manual only):** after a Mac-initiated reconnect, input can
  sometimes lag. Run `easyswitch-reconnect.sh --refresh` to drop and re-establish
  the link. This is deliberately **not** automatic: when an earlier version ran it
  on every reconnect, the Mac later could not reconnect or even re-pair the
  devices, and recovery required clearing macOS Bluetooth databases. The cause
  was not confirmed, but it is not worth the risk.

Result: switch back to the Mac and the devices reconnect within a few seconds.

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

Optional: change the check interval, e.g. `INTERVAL=3 ./install.sh`.

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

- Check the log: `cat /tmp/easyswitch-reconnect.err`
- Check the agent is loaded: `launchctl print gui/$(id -u)/com.easyswitch-reconnect`
- See what's connected: `blueutil --connected`
- Input lags after switching back: run `~/.local/bin/easyswitch-reconnect.sh --refresh`
  (you can bind it to a second hotkey). If that doesn't help, run
  `~/.local/bin/easyswitch-reconnect.sh --bt-cycle`, which turns Bluetooth off
  and on (same as the Control Center toggle; other devices like AirPods drop
  briefly).
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
