#!/usr/bin/env bash
# Test stream.conf parsing and variable defaults
set -uo pipefail

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

# Create a temp config file
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "==> Testing config file parsing"

# Test 1: Default values when no config exists
WIDTH="" HEIGHT="" FPS="" AWB="" LATENCY_MODE="" EXTRA_OPTS=""

: "${WIDTH:=1280}"
: "${HEIGHT:=720}"
: "${FPS:=24}"
: "${AWB:=auto}"
: "${LATENCY_MODE:=ultra_plus}"
: "${EXTRA_OPTS:=}"

test_case "Default WIDTH"        "1280"       "$WIDTH"
test_case "Default HEIGHT"       "720"        "$HEIGHT"
test_case "Default FPS"          "24"         "$FPS"
test_case "Default AWB"          "auto"        "$AWB"
test_case "Default LATENCY_MODE" "ultra_plus" "$LATENCY_MODE"
test_case "Default EXTRA_OPTS"   ""           "$EXTRA_OPTS"

# Test 2: Config file overrides defaults
cat > "$TEMP_DIR/stream.conf" << 'EOF'
WIDTH=640
HEIGHT=480
FPS=30
AWB=daylight
LATENCY_MODE=low
EXTRA_OPTS="--denoise off"
EOF

# Reset and source config
WIDTH="" HEIGHT="" FPS="" AWB="" LATENCY_MODE="" EXTRA_OPTS=""
# shellcheck disable=SC1091
source "$TEMP_DIR/stream.conf"

test_case "Config WIDTH"        "640"            "$WIDTH"
test_case "Config HEIGHT"       "480"            "$HEIGHT"
test_case "Config FPS"          "30"             "$FPS"
test_case "Config AWB"          "daylight"        "$AWB"
test_case "Config LATENCY_MODE" "low"            "$LATENCY_MODE"
test_case "Config EXTRA_OPTS"   "--denoise off"  "$EXTRA_OPTS"

# Test 3: Partial config (some values set, some default)
cat > "$TEMP_DIR/partial.conf" << 'EOF'
WIDTH=1920
HEIGHT=1080
EOF

WIDTH="" HEIGHT="" FPS="" AWB="" LATENCY_MODE="" EXTRA_OPTS=""
# shellcheck disable=SC1091
source "$TEMP_DIR/partial.conf"
: "${FPS:=24}"
: "${LATENCY_MODE:=ultra_plus}"

test_case "Partial config WIDTH"        "1920"       "$WIDTH"
test_case "Partial config HEIGHT"       "1080"       "$HEIGHT"
test_case "Partial config FPS default"  "24"         "$FPS"
test_case "Partial config LATENCY_MODE" "ultra_plus" "$LATENCY_MODE"

# Test 4: tuning file selection — evaluates the real block from publish.sh.j2
# so the test breaks if the fallback is ever dropped.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNING_BLOCK=$(sed -n '/^if \[\[ -n "\$TUNING_FILE" \]\]/,/^fi$/p' \
  "$REPO_ROOT/ansible/roles/traincam/templates/publish.sh.j2")
log() { :; }

if [[ -z "$TUNING_BLOCK" ]]; then
  echo "✗ could not extract TUNING_FILE block from publish.sh.j2"
  FAIL=$((FAIL + 1))
else
  touch "$TEMP_DIR/tuning.json"

  TUNING_FILE="$TEMP_DIR/tuning.json"; unset LIBCAMERA_RPI_TUNING_FILE
  eval "$TUNING_BLOCK"
  test_case "Existing tuning file is exported" "$TEMP_DIR/tuning.json" "${LIBCAMERA_RPI_TUNING_FILE:-}"

  TUNING_FILE="$TEMP_DIR/absent.json"; unset LIBCAMERA_RPI_TUNING_FILE
  eval "$TUNING_BLOCK"
  test_case "Missing tuning file falls back to libcamera" "" "${LIBCAMERA_RPI_TUNING_FILE:-}"

  TUNING_FILE=""; unset LIBCAMERA_RPI_TUNING_FILE
  eval "$TUNING_BLOCK"
  test_case "Empty tuning file uses libcamera default" "" "${LIBCAMERA_RPI_TUNING_FILE:-}"
fi

echo ""
echo "==> Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
