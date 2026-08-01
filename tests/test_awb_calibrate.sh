#!/usr/bin/env bash
# The AWB calibration maths and its plausibility guard.
# The guard matters: without it the script will happily suggest gains measured
# off centre-frame foliage, which makes the magenta cast worse rather than
# better. See scripts/awb-calibrate.sh for the full reasoning.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/awb-calibrate.sh"

fail=0
check() {
  if [ "$2" = "0" ]; then echo "  PASS: $1"; else echo "  FAIL: $1"; fail=1; fi
}

echo "awb-calibrate"

[ -f "$SCRIPT" ]; check "script exists" $?
[ -x "$SCRIPT" ]; check "script is executable" $?

bash -n "$SCRIPT" 2>/dev/null; check "script parses" $?

# Delegates to the script's own --check, which covers the gain correction
# maths in both directions plus the neutral-target guard.
"$SCRIPT" --check >/dev/null 2>&1; check "self-check passes" $?

# The guard must refuse a foliage-like patch. Proven by running the real
# script against a stub ffmpeg that emits green pixels, so this fails if
# someone widens the threshold enough to accept scenery.
stub=$(mktemp -d)
cat >"$stub/ffmpeg" <<'EOF'
#!/usr/bin/env bash
printf '\x64\x81\x5f'
EOF
chmod +x "$stub/ffmpeg"
out=$(PATH="$stub:$PATH" CONF=/dev/null SAMPLES=1 "$SCRIPT" 2>&1); rc=$?
[ "$rc" = "2" ]; check "refuses a foliage-coloured patch (exit 2)" $?
grep -q "REFUSING" <<<"$out"; check "explains the refusal" $?
rm -rf "$stub"

echo ""
[ "$fail" = "0" ] && echo "awb-calibrate: all passed" || echo "awb-calibrate: FAILURES"
exit "$fail"
