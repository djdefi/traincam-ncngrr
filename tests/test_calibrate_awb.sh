#!/usr/bin/env bash
# Guards scripts/calibrate_awb.py: the gain maths, and the thing that actually
# went wrong last time - calibrating in a different pipeline to the one that
# streams. The still path measured 1.046/1.032 where the video path measured
# 0.785/0.809 on the same scene, which invalidated a whole afternoon of A/Bs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/calibrate_awb.py"
GROUP_VARS="$ROOT/group_vars/traincam.yml"
pass=0
fail=0

check() {
  if [[ "$2" == "$3" ]]; then
    echo "✓ $1"
    pass=$((pass + 1))
  else
    echo "✗ $1: expected '$3', got '$2'"
    fail=$((fail + 1))
  fi
}

echo "==> Testing AWB calibration helper"

if python3 "$SCRIPT" self-test >/dev/null 2>&1; then
  check "gain maths self-test" "ok" "ok"
else
  python3 "$SCRIPT" self-test || true
  check "gain maths self-test" "failed" "ok"
fi

# The calibration must sample the SAME pipeline the stream uses. If someone
# retunes the template and not the tool, the measurement silently stops
# describing the stream - exactly the trap that cost us last time.
for setting in "--mode 1640:1232" "--codec mjpeg"; do
  if grep -qF -- "$setting" "$SCRIPT"; then
    got=yes
  else
    got=no
  fi
  check "calibration capture uses $setting" "$got" "yes"
done

# --mode lives in traincam_extra_opts, not the template. If it is retuned there
# and not in the tool, the calibration silently stops matching the stream.
if grep -qF -- "--mode 1640:1232" "$GROUP_VARS"; then
  deployed_mode=yes
else
  deployed_mode=no
fi
check "stream still uses --mode 1640:1232 (else update both)" "$deployed_mode" "yes"

# The tuning file is part of the streamed pipeline too. Without --tuning-file
# the tool lets libcamera auto-load the stock imx219.json (Bayesian AWB) instead
# of the deployed tuning the stream forces (grey-world when noir was fitted), and the SAME scene
# then measured 1.56 vs 0.11 distance on 2026-08-01 - a different camera. The
# mode/codec checks above guard this trap for size; this guards it for colour.
#
# Grepping the file text is NOT enough: "--tuning-file" also appears in the
# comments and the TUNING constant, so a text grep passes even after the flag is
# dropped from the real command. Import the module and inspect the assembled
# CAPTURE string that actually runs - that is the only thing that can fail.
tuning_path="$(grep -E '^traincam_tuning_file:' "$GROUP_VARS" | awk '{print $2}' | tr -d '"'\''')"
if PYTHONPATH="$ROOT/scripts" python3 -c "
import sys, calibrate_awb as c
sys.exit(0 if ('--tuning-file' in c.CAPTURE and '$tuning_path' in c.CAPTURE) else 1)
" 2>/dev/null; then
  tuning_ok=yes
else
  tuning_ok=no
fi
check "capture command pins the stream's tuning file ($tuning_path)" "$tuning_ok" "yes"

# rpicam-jpeg is the still path. It lies about what the stream shows.
if grep -q "rpicam-jpeg" "$SCRIPT"; then
  still=yes
else
  still=no
fi
check "calibration never uses the still path (rpicam-jpeg)" "$still" "no"

# A capture stops the stream. It must come back even if the capture fails.
if grep -q "trap 'sudo systemctl start traincam' EXIT" "$SCRIPT"; then
  trapped=yes
else
  trapped=no
fi
check "stream restarts even if the capture fails" "$trapped" "yes"

echo
echo "==> Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
