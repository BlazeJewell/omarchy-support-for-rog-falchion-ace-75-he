# Omarchy support for ROG Falchion Ace 75 HE

An Omarchy plugin for the **ASUS ROG Falchion Ace 75 HE** (USB `0b05:1c7d`),
without Armoury Crate or Gear Link:

- **Lighting:** effect (static, breathing, colour cycle, wave, ripple, reactive,
  starry night, rain drop), colour or rainbow, speed, wave direction, brightness.
- **Key travel:** the actuation point for all keys, 0.1–3.5 mm. While the slider
  moves, the light bar along the top of the keyboard shows the travel, as the
  keyboard's own control does; the other keys keep their lighting.
- **Rapid Trigger:** shows ON or OFF. It follows the switch on the keyboard; the
  firmware does not let software turn it on or off.

Changes apply straight away and are saved to the keyboard a moment after the
last one, so they stay after unplugging or rebooting.

It works in the stock Omarchy bar and as a section of
[jake.sidebar](https://github.com/BlazeJewell/omarchy-sidebar).

## Install

```bash
gh repo clone BlazeJewell/omarchy-support-for-rog-falchion-ace-75-he ~/.config/omarchy/plugins/jake.keyboard-light
omarchy plugin enable jake.keyboard-light
```

The keyboard's control interface is root-only by default. Let the logged-in user
reach it with a udev rule (once per machine):

```bash
sudo tee /etc/udev/rules.d/60-rog-falchion-ace-75-he.rules >/dev/null <<'EOF'
SUBSYSTEMS=="usb|hidraw", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1c7d", TAG+="uaccess"
EOF
sudo udevadm control --reload && sudo udevadm trigger
```

## How it works

`kbd.py` talks to the keyboard's vendor HID interface (interface 1, usage page
`0xFF00`, 64-byte reports, no report ID). Settings are kept in
`~/.config/omarchy/keyboard-light.json`.

| Command | Bytes | Source |
| --- | --- | --- |
| Firmware version | `12 00` | OpenRGB (ASUS Aura keyboards) |
| Set effect | `51 2C mode 00 speed brightness colour-mode direction 02 …` | OpenRGB |
| Per-LED colour | `C0 81 count 00 (led r g b)…` | OpenRGB |
| Save to keyboard | `50 55` | OpenRGB and Gear Link |
| Read / set key travel (all keys) | `25 05` / `51 50 00 00 lo hi`, in 0.01 mm | Gear Link (pid 7293) |
| Read Rapid Trigger | `25 00` (byte 4) | Gear Link |

The keyboard answers `51 5C` (set Rapid Trigger) with `ff aa`, and Gear Link
never sends it for this model, so Rapid Trigger stays on the physical switch.

The light bar is LEDs `16 40 72 96 120 152 17 41 73 97 121 153`, left to right.
They were found by lighting groups of LEDs and noting which ones lit.

```bash
./kbd.py status
./kbd.py apply mode=wave rainbow=1 speed=60 brightness=4 direction=left --save
./kbd.py travel 1.2 --preview
./kbd.py restore
```

Speed runs on a log scale between `SLOWEST` and `FASTEST` at the top of
`kbd.py`, because the keyboard's speed value behaves like a duration.
