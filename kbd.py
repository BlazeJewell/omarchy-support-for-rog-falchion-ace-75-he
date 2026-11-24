#!/usr/bin/env python3
"""Lighting, key travel and Rapid Trigger for the ASUS ROG Falchion Ace 75 HE (USB 0b05:1c7d).

The keyboard speaks the same vendor protocol as the ROG keyboards OpenRGB
supports (64-byte reports on interface 1, usage page 0xFF00): 0x51 0x2C sets a
built-in effect, 0x50 0x55 saves it to the keyboard, 0x12 0x00 reads the
firmware. Key travel and Rapid Trigger use the commands ASUS's Gear Link web
app sends (read from its device bundle for pid 7293): 0x25 0x05 / 0x51 0x50 read
and set the actuation point for all keys in 0.01 mm (10..350), 0x25 0x00 reads
Rapid Trigger. Its on/off is the keyboard's own switch: this firmware answers
0x51 0x5C (set) with ff aa, and Gear Link never sends it for this model. Needs the udev rule in README.md so the
logged-in user can open it.

usage:
  kbd.py status                 JSON: found, access, firmware, saved settings
  kbd.py apply [--save] KEY=VALUE ...
      mode=static|breathing|cycle|reactive|wave|ripple|starry|rain
      color=rrggbb  speed=0..100 (slow..fast)  brightness=0..4
      direction=left|right|up|down  rainbow=0|1
  kbd.py travel <mm> [--preview]  actuation point for all keys, 0.1..3.5 mm;
                                --preview shows it on the light bar like the keyboard does
  kbd.py restore                show the saved effect again (after a preview)
  kbd.py save                   save everything to the keyboard
"""
import glob
import json
import os
import select
import sys

VID, PID = 0x0B05, 0x1C7D
STATE = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                     "omarchy", "keyboard-light.json")
MODES = {"static": 0, "breathing": 1, "cycle": 2, "reactive": 3, "wave": 4,
         "ripple": 5, "starry": 6, "rain": 9}
DIRECTIONS = {"right": 0, "down": 2, "left": 4, "up": 6}
DEFAULTS = {"mode": "static", "color": "00b3b3", "speed": 50, "brightness": 4,
            "direction": "left", "rainbow": 0}
SLOWEST, FASTEST = 90, 8   # keyboard speed values at the slider's 0 % and 100 %
TRAVEL_MIN, TRAVEL_MAX = 10, 350   # actuation point, in 0.01 mm (Gear Link: minAP/maxAP)
# The light bar along the top edge, left to right (found by lighting LEDs one
# group at a time: the first six F-key columns, then the same columns + 1).
BAR = [16, 40, 72, 96, 120, 152, 17, 41, 73, 97, 121, 153]
RAINBOW = ["ff0000", "ff8000", "ffff00", "00ff00", "00ffff", "0000ff", "ff00ff"]


def find():
    """The keyboard's vendor hidraw node, or None."""
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            uevent = open(h + "/device/uevent").read().upper()
            desc = open(h + "/device/report_descriptor", "rb").read()
        except OSError:
            continue
        if "%08X:%08X" % (VID, PID) in uevent and desc[:3] == b"\x06\x00\xff":
            return "/dev/" + os.path.basename(h)
    return None


def drain(fd, wait=0.0):
    out = []
    while select.select([fd], [], [], wait)[0]:
        out.append(os.read(fd, 64))
        wait = 0.02
    return out


def send(fd, data, wait=0.06):
    data = bytes(data)[:64]
    os.write(fd, b"\0" + data + bytes(64 - len(data)))  # no report id
    return drain(fd, wait)


def rgb(hexstr):
    hexstr = str(hexstr).strip().lstrip("#").lower()
    if len(hexstr) != 6 or any(c not in "0123456789abcdef" for c in hexstr):
        raise ValueError("colour must be rrggbb")
    return bytes.fromhex(hexstr)


def load():
    s = dict(DEFAULTS)
    try:
        with open(STATE) as f:
            saved = json.load(f)
        if isinstance(saved, dict):
            s.update({k: saved[k] for k in DEFAULTS if k in saved})
    except (OSError, ValueError):
        pass
    return s


def clean(s):
    out = dict(DEFAULTS)
    out["mode"] = s.get("mode") if s.get("mode") in MODES else DEFAULTS["mode"]
    try:
        rgb(s.get("color", "")); out["color"] = str(s["color"]).lstrip("#").lower()
    except (ValueError, KeyError):
        pass
    out["speed"] = max(0, min(100, int(float(s.get("speed", DEFAULTS["speed"])))))
    out["brightness"] = max(0, min(4, int(float(s.get("brightness", DEFAULTS["brightness"])))))
    out["direction"] = s.get("direction") if s.get("direction") in DIRECTIONS else DEFAULTS["direction"]
    out["rainbow"] = 1 if str(s.get("rainbow", 1)) in ("1", "true", "True") else 0
    return out


def packet(s):
    """The 0x51 0x2C effect report for settings s (OpenRGB's per-key layout)."""
    mode = MODES[s["mode"]]
    # The keyboard takes 255 (slowest) .. 0 (fastest), but the value acts like a
    # duration: 0 is far too fast and anything over ~100 crawls. So the slider
    # spans SLOWEST..FASTEST on a log scale, where equal steps feel equal.
    speed = round(SLOWEST * (FASTEST / SLOWEST) ** (s["speed"] / 100))
    brightness = s["brightness"] * 25            # 0, 25, 50, 75, 100
    color_mode = 0
    if s["mode"] in ("breathing", "reactive", "starry", "rain"):
        color_mode = 1 if s["rainbow"] else 16   # 1 random colours, 16 the chosen one
    direction = DIRECTIONS[s["direction"]] if s["mode"] == "wave" else 0
    p = bytearray([0x51, 0x2C, mode, 0x00, speed, brightness, color_mode, direction, 0x02])
    if s["mode"] in ("wave", "ripple"):
        colors = RAINBOW if s["rainbow"] else [s["color"]]
        p.append(len(colors))
        for i, c in enumerate(colors):
            p += bytes([round(100 / len(colors) * (i + 1))]) + rgb(c)
    elif s["mode"] != "cycle":
        p += rgb(s["color"])
    return p


def direct(fd, colors):
    """Per-LED colours {index: bytes(rgb)}, only for the LEDs given."""
    leds = sorted(colors)
    for i in range(0, len(leds), 15):
        chunk = leds[i:i + 15]
        body = bytearray([0xC0, 0x81, len(chunk), 0x00])
        for l in chunk:
            body += bytes([l]) + colors.get(l, b"\0\0\0")
        send(fd, body, 0.01)


def preview_travel(fd, value, s):
    """Light the bar from the left like the panel's slider: the lowest travel
    lights one LED, and it fills to the right as the travel gets deeper.
    Only the bar's LEDs are sent; the other keys keep their effect."""
    lit = max(1, round((value - TRAVEL_MIN) / (TRAVEL_MAX - TRAVEL_MIN) * (len(BAR) - 1)) + 1)
    on = rgb(s["color"]) if s["mode"] != "cycle" and not s["rainbow"] else b"\xff\xff\xff"
    dim = bytes(c // 10 for c in on)
    direct(fd, {led: (on if i < lit else dim) for i, led in enumerate(BAR)})


def status():
    dev = find()
    out = {"found": dev is not None, "access": False, "firmware": "", "settings": load()}
    if dev:
        try:
            fd = os.open(dev, os.O_RDWR)
        except OSError:
            return out
        out["access"] = True
        drain(fd)
        r = send(fd, [0x12, 0x00], 0.3)
        if r and r[0][:2] == b"\x12\x00" and len(r[0]) > 6:
            out["firmware"] = "%X.%02X.%02X" % (r[0][6], r[0][5], r[0][4])
        r = send(fd, [0x25, 0x05], 0.3)
        if r and r[0][:2] == b"\x25\x05":
            out["travel"] = (r[0][5] << 8 | r[0][4]) / 100
        r = send(fd, [0x25, 0x00], 0.3)
        if r and r[0][:2] == b"\x25\x00":
            out["rapidTrigger"] = r[0][4] == 1
        os.close(fd)
    return out


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "status":
        print(json.dumps(status()))
        return 0
    if cmd not in ("apply", "save", "travel", "restore"):
        print(__doc__.strip())
        return 2
    dev = find()
    if not dev:
        print("keyboard not found", file=sys.stderr)
        return 1
    try:
        fd = os.open(dev, os.O_RDWR)
    except PermissionError:
        print("no permission for %s: install the udev rule (README.md)" % dev, file=sys.stderr)
        return 1
    drain(fd)
    if cmd == "apply":
        s = load()
        for arg in argv[2:]:
            if arg == "--save":
                continue
            k, _, v = arg.partition("=")
            if k in DEFAULTS:
                s[k] = v
        s = clean(s)
        send(fd, packet(s))
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        tmp = STATE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(s, f)
        os.replace(tmp, STATE)
    if cmd == "travel":
        try:
            v = round(float(argv[2]) * 100)
        except (IndexError, ValueError):
            print("travel takes millimetres, 0.1..3.5", file=sys.stderr)
            return 2
        v = max(TRAVEL_MIN, min(TRAVEL_MAX, v))
        send(fd, [0x51, 0x50, 0x00, 0x00, v & 0xFF, v >> 8])
        if "--preview" in argv:
            preview_travel(fd, v, clean(load()))
    if cmd == "restore":
        send(fd, packet(clean(load())))
    if cmd == "save" or "--save" in argv:
        send(fd, [0x50, 0x55], 0.3)
    os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
