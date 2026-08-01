#!/usr/bin/env python3
"""Measure white balance gains at the venue and check the result.

The NoIR tuning file ships rpi.awb = {"bayes": 0}: Bayesian AWB is switched
off, so --awb is a no-op and libcamera falls back to grey-world. Grey-world
assumes the frame averages to grey, which makes the calibration trivial as
long as a white card FILLS THE FRAME. Point the camera at white paper under
the venue's own lighting, run this, paste the number it prints.

  ./scripts/calibrate_awb.py measure     # white card filling the frame
  ./scripts/calibrate_awb.py verify      # normal scene, after deploying

measure is authoritative; verify is only a rough smoke test. On a NORMAL scene
verify samples the brightest pixels of the whole frame, which is exactly what
grey-world optimises, so it structurally flatters --awb auto and penalises any
fixed --awbgains lock - a good lock can read "BAD" next to a window or coloured
scenery. Judge a lock with measure and a white card, not verify. (A wrong
tuning file makes verify worse still: see the CAPTURE note below.)

ponytail: runs over ssh from the laptop rather than deploying to the Pi. It is
a bench tool, not a runtime component, so it stays out of the Ansible surface.
"""

import argparse
import json
import statistics
import subprocess
import sys

HOST = "train@traincam1.local"

# Kept in step with publish.sh.j2 by test_calibrate_awb.sh, which fails if the
# template's mode/size/framerate OR the tuning file stop matching. Measuring in
# a different pipeline to the one that streams is how the last calibration went
# wrong, and the tuning file is part of that pipeline: without --tuning-file,
# libcamera auto-loads the stock imx219.json (Bayesian AWB) instead of the
# deployed noir grey-world tuning, and the same scene then measured 1.56 vs 0.11
# distance on 2026-08-01. TUNING is exactly what publish.sh loads.
TUNING = "/etc/traincam/tuning.json"
CAPTURE = (
    "rpicam-vid --nopreview -t 4000 --codec mjpeg "
    "--width 1280 --height 720 --framerate 24 --mode 1640:1232 "
    f"--tuning-file {TUNING}"
)


def median_gains(metadata):
    """Median red/blue gain over the captured frames.

    Median not mean: AWB takes a few frames to settle, and the early outliers
    would drag a mean toward whatever the camera guessed before it converged.
    """
    frames = metadata if isinstance(metadata, list) else [metadata]
    pairs = [f["ColourGains"] for f in frames if "ColourGains" in f]
    if not pairs:
        raise ValueError("no ColourGains in metadata - did the capture fail?")
    return (
        statistics.median(p[0] for p in pairs),
        statistics.median(p[1] for p in pairs),
    )


def neutrality(r_over_g, b_over_g):
    """Distance from neutral. 1.000/1.000 is perfect grey.

    Returns (distance, verdict). Both ratios above 1 is magenta, both below is
    green; that symmetry is also the IR signature on a NoIR module, because IR
    lands in red and blue together.
    """
    dist = abs(r_over_g - 1.0) + abs(b_over_g - 1.0)
    if dist < 0.10:
        verdict = "good"
    elif dist < 0.25:
        verdict = "acceptable"
    else:
        verdict = "BAD - recalibrate"
    return dist, verdict


def _ssh(script):
    done = subprocess.run(
        ["ssh", HOST, script], capture_output=True, text=True, timeout=180
    )
    if done.returncode != 0:
        sys.exit(f"ssh failed:\n{done.stderr}")
    return done.stdout


def _capture(extra_args, want):
    """Run a capture on the Pi, always restarting the stream afterwards."""
    out = "/tmp/cal_md.json" if want == "metadata" else "/tmp/cal_%03d.jpg"
    sink = "/dev/null" if want == "metadata" else out
    meta = f"--metadata /tmp/cal_md.json --metadata-format json" if want == "metadata" else ""
    seg = "" if want == "metadata" else "--segment 1"
    script = f"""
set -u
sudo systemctl stop traincam
trap 'sudo systemctl start traincam' EXIT
rm -f /tmp/cal_md.json /tmp/cal_*.jpg
{CAPTURE} {extra_args} {meta} {seg} -o {sink} >/dev/null 2>&1
"""
    if want == "metadata":
        script += "cat /tmp/cal_md.json; rm -f /tmp/cal_md.json\n"
    else:
        script += """
python3 - <<'PY'
import glob, json
from PIL import Image
f = sorted(glob.glob('/tmp/cal_*.jpg'))[-1]
px = list(Image.open(f).convert('RGB').getdata())
c = [p for p in px if 120 < sum(p)/3 < 235]
c.sort(key=lambda p: -sum(p))
s = c[:len(c)//50 or 1]
n = len(s)
print(json.dumps({'r': sum(p[0] for p in s)/n,
                  'g': sum(p[1] for p in s)/n,
                  'b': sum(p[2] for p in s)/n}))
PY
rm -f /tmp/cal_*.jpg
"""
    return _ssh(script)


def measure():
    print("Fill the frame with white paper under the venue lighting, then wait...")
    raw = _capture("--awb auto", "metadata")
    r, b = median_gains(json.loads(raw))
    print(f"\n  measured gains: red {r:.3f}  blue {b:.3f}\n")
    print("Put this in group_vars/traincam.yml, then run the playbook:\n")
    print(f'  traincam_awb_gains: "{r:.2f},{b:.2f}"\n')
    print("Then: ./scripts/calibrate_awb.py verify")


def verify():
    print("Point the camera at the normal scene, then wait...")
    s = json.loads(_capture("", "image"))
    rg, bg = s["r"] / s["g"], s["b"] / s["g"]
    dist, verdict = neutrality(rg, bg)
    cast = "magenta" if rg > 1 and bg > 1 else "green" if rg < 1 and bg < 1 else "mixed"
    print(f"\n  R/G {rg:.3f}   B/G {bg:.3f}   distance {dist:.3f}   {verdict}")
    if verdict != "good":
        print(f"  cast looks {cast}; re-run measure with the white card")
    sys.exit(0 if verdict != "BAD - recalibrate" else 1)


def self_test():
    # Median ignores the unconverged first frames rather than averaging them in.
    md = [{"ColourGains": [9.0, 9.0]}] + [{"ColourGains": [1.0, 2.0]}] * 5
    assert median_gains(md) == (1.0, 2.0), median_gains(md)
    # A single dict, not a list, is what a one-frame capture yields.
    assert median_gains({"ColourGains": [1.5, 2.5]}) == (1.5, 2.5)
    # Frames without gains are skipped, not treated as zero.
    assert median_gains([{"Lux": 3}, {"ColourGains": [1.0, 2.0]}]) == (1.0, 2.0)
    try:
        median_gains([{"Lux": 3}])
    except ValueError:
        pass
    else:
        raise AssertionError("empty metadata must raise, not return a default")

    assert neutrality(1.0, 1.0)[1] == "good"
    # The gains shipped in 54ab392 score 0.109 - "acceptable", not "good". Left
    # honest rather than widening the threshold to flatter the answer: that is
    # a real ~9% blue excess, and it is calibrated for one room anyway.
    assert neutrality(0.985, 1.094)[1] == "acceptable"
    assert neutrality(1.283, 1.335)[1] == "BAD - recalibrate"  # auto, same scene
    assert neutrality(0.785, 0.809)[1] == "BAD - recalibrate"  # the green cast
    # Distance is symmetric: a magenta and a green miss of equal size score equal.
    assert neutrality(1.2, 1.2)[0] == neutrality(0.8, 0.8)[0]
    print("calibrate_awb self-test: all assertions passed")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("action", choices=["measure", "verify", "self-test"])
    action = ap.parse_args().action
    {"measure": measure, "verify": verify, "self-test": self_test}[action]()
