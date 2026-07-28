#!/usr/bin/env python3
"""Write a libcamera tuning file with a shutter-first AGC ladder.

libcamera's stock AGC spends exposure time before it reaches for gain, which is
right for stills and wrong for a camera bolted to a moving train: it parks at
1/33s and smears everything. The --exposure sport control that would fix this is
ignored by the libcamera build on Bookworm (normal/sport/long all return an
identical exposure time), so the ladder has to be replaced in the tuning file.

Usage: patch_tuning.py SRC DST [SHUTTER_JSON GAIN_JSON]

With no ladder given, SRC is copied through unchanged. Prints "changed" or
"unchanged" so the caller can report idempotency honestly.
"""
import json
import os
import sys


def find_agc(doc):
    """Tuning files are either {"algorithms": [{"rpi.agc": {...}}, ...]} or flat."""
    algorithms = doc.get("algorithms")
    if isinstance(algorithms, list):
        for entry in algorithms:
            if isinstance(entry, dict) and "rpi.agc" in entry:
                return entry["rpi.agc"]
    return doc.get("rpi.agc")


def main(argv):
    if len(argv) not in (3, 5):
        sys.stderr.write(__doc__)
        return 2
    src, dst = argv[1], argv[2]

    with open(src) as fh:
        doc = json.load(fh)

    if len(argv) == 5:
        shutter = json.loads(argv[3])
        gain = json.loads(argv[4])
        if len(shutter) != len(gain):
            sys.stderr.write("shutter and gain ladders must be the same length\n")
            return 2
        if sorted(shutter) != shutter or sorted(gain) != gain:
            sys.stderr.write("shutter and gain ladders must be non-decreasing\n")
            return 2
        agc = find_agc(doc)
        # A colour or exposure problem must not take the camera offline, so an
        # unrecognised tuning file is copied through rather than rejected.
        if agc is None or "exposure_modes" not in agc:
            sys.stderr.write("WARNING: no rpi.agc exposure_modes in %s, copying verbatim\n" % src)
        else:
            agc["exposure_modes"]["normal"] = {"shutter": shutter, "gain": gain}

    new = json.dumps(doc, indent=2, sort_keys=True)
    old = None
    if os.path.exists(dst):
        with open(dst) as fh:
            old = fh.read()
    if old == new:
        print("unchanged")
        return 0
    with open(dst, "w") as fh:
        fh.write(new)
    print("changed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
