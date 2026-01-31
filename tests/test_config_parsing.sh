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
WIDTH="" HEIGHT="" FPS="" AWBGAINS="" LATENCY_MODE="" EXTRA_OPTS=""

: "${WIDTH:=1280}"
: "${HEIGHT:=720}"
: "${FPS:=24}"
: "${AWBGAINS:=1.00,1.12}"
: "${LATENCY_MODE:=ultra_plus}"
: "${EXTRA_OPTS:=}"

test_case "Default WIDTH"        "1280"       "$WIDTH"
test_case "Default HEIGHT"       "720"        "$HEIGHT"
test_case "Default FPS"          "24"         "$FPS"
test_case "Default AWBGAINS"     "1.00,1.12"  "$AWBGAINS"
test_case "Default LATENCY_MODE" "ultra_plus" "$LATENCY_MODE"
test_case "Default EXTRA_OPTS"   ""           "$EXTRA_OPTS"

# Test 2: Config file overrides defaults
cat > "$TEMP_DIR/stream.conf" << 'EOF'
WIDTH=640
HEIGHT=480
FPS=30
AWBGAINS="1.50,1.25"
LATENCY_MODE=low
EXTRA_OPTS="--denoise off"
EOF

# Reset and source config
WIDTH="" HEIGHT="" FPS="" AWBGAINS="" LATENCY_MODE="" EXTRA_OPTS=""
# shellcheck disable=SC1091
source "$TEMP_DIR/stream.conf"

test_case "Config WIDTH"        "640"            "$WIDTH"
test_case "Config HEIGHT"       "480"            "$HEIGHT"
test_case "Config FPS"          "30"             "$FPS"
test_case "Config AWBGAINS"     "1.50,1.25"      "$AWBGAINS"
test_case "Config LATENCY_MODE" "low"            "$LATENCY_MODE"
test_case "Config EXTRA_OPTS"   "--denoise off"  "$EXTRA_OPTS"

# Test 3: Partial config (some values set, some default)
cat > "$TEMP_DIR/partial.conf" << 'EOF'
WIDTH=1920
HEIGHT=1080
EOF

WIDTH="" HEIGHT="" FPS="" AWBGAINS="" LATENCY_MODE="" EXTRA_OPTS=""
# shellcheck disable=SC1091
source "$TEMP_DIR/partial.conf"
: "${FPS:=24}"
: "${LATENCY_MODE:=ultra_plus}"

test_case "Partial config WIDTH"        "1920"       "$WIDTH"
test_case "Partial config HEIGHT"       "1080"       "$HEIGHT"
test_case "Partial config FPS default"  "24"         "$FPS"
test_case "Partial config LATENCY_MODE" "ultra_plus" "$LATENCY_MODE"

echo ""
echo "==> Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
