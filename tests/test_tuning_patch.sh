#!/usr/bin/env bash
# Test the AGC tuning patcher. A bad tuning file means a dead camera at the
# fair, so the fallback and validation paths matter more than the happy path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCHER="$REPO_ROOT/ansible/roles/traincam/files/patch_tuning.py"

PASS=0
FAIL=0
test_case() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "✓ $name"
    PASS=$((PASS + 1))
  else
    echo "✗ $name: expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

echo "==> Testing AGC tuning patcher"

if ! command -v python3 >/dev/null 2>&1; then
  echo "! python3 not installed, skipping"
  exit 0
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

cat > "$TEMP_DIR/src.json" <<'EOF'
{"version": 2.0, "algorithms": [
  {"rpi.awb": {"bayes": 1}},
  {"rpi.agc": {"exposure_modes": {
    "normal": {"shutter": [100, 30000], "gain": [1.0, 4.0]},
    "short":  {"shutter": [100, 10000], "gain": [1.0, 4.0]}}}}]}
EOF

SHUTTER='[100, 2500, 20000]'
GAIN='[1.0, 4.0, 8.0]'

out=$(python3 "$PATCHER" "$TEMP_DIR/src.json" "$TEMP_DIR/out.json" "$SHUTTER" "$GAIN" 2>&1)
test_case "First run reports changed" "changed" "$out"

read -r got_shutter got_gain got_short got_awb <<< "$(python3 - "$TEMP_DIR/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
agc = next(a["rpi.agc"] for a in d["algorithms"] if "rpi.agc" in a)
awb = next(a["rpi.awb"] for a in d["algorithms"] if "rpi.awb" in a)
n = agc["exposure_modes"]["normal"]
print(json.dumps(n["shutter"]).replace(" ", ""),
      json.dumps(n["gain"]).replace(" ", ""),
      json.dumps(agc["exposure_modes"]["short"]["shutter"]).replace(" ", ""),
      awb["bayes"])
PY
)"

test_case "Normal shutter ladder replaced" "[100,2500,20000]" "$got_shutter"
test_case "Normal gain ladder replaced"    "[1.0,4.0,8.0]"    "$got_gain"
test_case "Other exposure modes preserved" "[100,10000]"      "$got_short"
test_case "Unrelated algorithms preserved" "1"                "$got_awb"

out=$(python3 "$PATCHER" "$TEMP_DIR/src.json" "$TEMP_DIR/out.json" "$SHUTTER" "$GAIN" 2>&1)
test_case "Re-run is idempotent" "unchanged" "$out"

python3 "$PATCHER" "$TEMP_DIR/src.json" "$TEMP_DIR/bad.json" '[100, 200]' "$GAIN" >/dev/null 2>&1
test_case "Mismatched ladder lengths rejected" "2" "$?"

python3 "$PATCHER" "$TEMP_DIR/src.json" "$TEMP_DIR/bad.json" '[20000, 100]' '[1.0, 4.0]' >/dev/null 2>&1
test_case "Decreasing shutter ladder rejected" "2" "$?"

# An unrecognised tuning file must still yield a usable file, not an error.
# The channels[] schema: every current sensor (imx219, imx477, imx708) nests
# exposure_modes one level down, one per HDR channel. Fitting an imx219 with
# only the flat schema supported silently shipped its stock 30000us ladder.
cat > "$TEMP_DIR/channels.json" <<'EOF'
{"version": 2.0, "algorithms": [
  {"rpi.agc": {"channels": [
    {"base_ev": 1.0, "exposure_modes": {
      "normal": {"shutter": [100, 30000], "gain": [1.0, 4.0]},
      "short":  {"shutter": [100, 10000], "gain": [1.0, 4.0]}}},
    {"base_ev": 0.5, "exposure_modes": {
      "normal": {"shutter": [100, 60000], "gain": [1.0, 8.0]}}}]}}]}
EOF

out=$(python3 "$PATCHER" "$TEMP_DIR/channels.json" "$TEMP_DIR/ch_out.json" "$SHUTTER" "$GAIN" 2>&1)
test_case "channels[] schema reports changed, no warning" "changed" "$out"

read -r ch0 ch1 ch0_short ch1_ev <<< "$(python3 - "$TEMP_DIR/ch_out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ch = next(a["rpi.agc"] for a in d["algorithms"] if "rpi.agc" in a)["channels"]
j = lambda v: json.dumps(v).replace(" ", "")
print(j(ch[0]["exposure_modes"]["normal"]["shutter"]),
      j(ch[1]["exposure_modes"]["normal"]["shutter"]),
      j(ch[0]["exposure_modes"]["short"]["shutter"]),
      ch[1]["base_ev"])
PY
)"

test_case "channels[0] ladder replaced"        "[100,2500,20000]" "$ch0"
test_case "channels[1] ladder replaced"        "[100,2500,20000]" "$ch1"
test_case "channels[] other modes preserved"   "[100,10000]"      "$ch0_short"
test_case "channels[] sibling keys preserved"  "0.5"              "$ch1_ev"

echo '{"version": 2.0, "algorithms": [{"rpi.awb": {"bayes": 1}}]}' > "$TEMP_DIR/noagc.json"
python3 "$PATCHER" "$TEMP_DIR/noagc.json" "$TEMP_DIR/noagc_out.json" "$SHUTTER" "$GAIN" >/dev/null 2>&1
test_case "Missing rpi.agc still succeeds" "0" "$?"
test_case "Missing rpi.agc still writes a file" "yes" \
  "$([[ -s "$TEMP_DIR/noagc_out.json" ]] && echo yes || echo no)"

echo ""
echo "==> Results: $PASS passed, $FAIL failed"
[[ $FAIL -gt 0 ]] && exit 1
exit 0
