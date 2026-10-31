# arctis-omni-linux

Linux controls for the **SteelSeries Arctis Nova Pro Omni** (GameHub `1038:2290`):
noise cancelling / transparency, mic sidetone, a working ChatMix dial, and a KDE Plasma
panel widget with the battery level and status.

SteelSeries GG is Windows-only. This talks to the GameHub directly over `hidraw`, with
no kernel module or GG install.

## What you get

- **`arctis-omni`**: a small Python CLI.
  ```
  arctis-omni status [--json]           # battery, spare battery, noise mode, sidetone, mic, dial
  arctis-omni anc off|transparency|anc
  arctis-omni anc-level 1-3
  arctis-omni transparency-level 1-10
  arctis-omni sidetone on|off|1-10
  ```
- **ChatMix**: a user service plus PipeWire config that adds two outputs, **Arctis Omni Game**
  and **Arctis Omni Chat**, both routed to the headset. The dial on the GameHub sets their
  volumes.
- **Plasma 6 widget** ("Arctis Omni Battery"): headset battery in the panel, and a popup
  with full status, Off / Transparency / ANC buttons and a sidetone slider.
- **udev rule** so your user can open the GameHub's `hidraw` node without root.

## Install

Requirements: Python 3, PipeWire with `pipewire-pulse` (`pactl`), systemd user services,
and Plasma 6 for the widget.

```sh
./install.sh                 # uses sudo for the udev rule
SUDO=pkexec ./install.sh     # or a graphical password prompt
```

Then:

1. Set your default output to **Arctis Omni Game** and your voice app's output (Discord etc.)
   to **Arctis Omni Chat**. Apps that play to the raw "Arctis Nova Pro Omni" output aren't
   affected by the dial.
2. Add **Arctis Omni Battery** to a panel (right-click the panel → Add Widgets).

`./uninstall.sh` removes everything and puts the hub back into hardware ChatMix mode.

## How ChatMix works

The GameHub doesn't mix game and chat audio itself for a single PC. Its hardware mix only
blends its two USB inputs (PC on USB-1 vs. an Xbox). On Windows, GG switches the hub into
**software ChatMix** mode, and the Sonar app does the mixing on the PC. This project does
the same: `arctis-omni chatmix-daemon` enables software mode, listens for dial events, and
sets the Game/Chat sink volumes with `pactl`. When the service stops, it switches the hub
back to hardware mode.

The loopback sinks use `node.dont-fallback` + `node.linger`. If the headset disappears, they
wait for it instead of moving your game audio to the speakers.

## Protocol

Commands are 64-byte HID output reports with **report ID `0x01`** on the **usage page
`0xFFC0`** collection (interface 3). The hub sends events as **report ID `0x07`** on the same
collection, interleaved with command replies, so filter on both bytes.

| Function | Command | Notes |
|---|---|---|
| Status | `01 B0` → `01 B0 …` | `[6]` headset battery %, `[7]` spare battery %, `[8]` transparency level, `[9]` mic mute, `[10]` noise mode, `[14]` link state (`0x08` = connected), `[15]` charging state, `[16]` ANC level |
| Noise mode | `01 BD <mode>` | `0` off, `1` transparency, `2` ANC |
| ANC level | `01 B8 <1-3>` | |
| Transparency level | `01 B9 <1-10>` | |
| Mic sidetone | `01 38 <on 0/1> <level 1-10>` | |
| Software ChatMix | `01 49 <0/1>` | `1`: hub reports the dial instead of mixing |
| Settings block | `01 20`, then a `HIDIOCGFEATURE` read of report 1 (1037 bytes) | Starts at the command byte. From offset 141: `+4` mic volume, `+5` sidetone level, `+10`/`+11` ChatMix game/chat, `+28` sidetone on/off |

| Event | Meaning |
|---|---|
| `07 45 <game> <chat>` | ChatMix dial. Each channel's volume is 0-100; the centre is 100/100, and turning towards one side fades the other channel to 0 |
| `07 B7 <headset> <spare> <charging>` | Battery change |

**Verified on hardware** (firmware 1.32.0): status/battery fields, noise mode switching,
sidetone set and read back, ChatMix enable plus dial events. **Not yet verified:** the
ANC/transparency *level* writes and the charging value of `[15]`.

The command set was derived from SteelSeries GG's device definitions, for interoperability,
and then checked against the hardware as above.

## Battery in HeadsetControl

[HeadsetControl](https://github.com/Sapd/HeadsetControl) support for this headset is in
progress in [PR #584](https://github.com/Sapd/HeadsetControl/pull/584). As posted, that PR
reads 0% battery on Linux because of the interleaved `0x07` events. See the
[review comment](https://github.com/Sapd/HeadsetControl/pull/584#issuecomment-6550334589)
for the fix. This project doesn't need HeadsetControl.

## License

MIT
