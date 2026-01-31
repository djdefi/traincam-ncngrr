#!/usr/bin/env bash
# Test latency mode keyframe interval calculation
# This tests the logic from publish.sh.j2 / stream.sh
set -uo pipefail

PASS=0
FAIL=0

test_case() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "✓ $name"
    PASS=$((PASS + 1))
  else
    echo "✗ $name: expected $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

# Simulate the latency mode calculation logic from publish.sh.j2
calculate_keyframe_interval() {
  local fps="$1" mode="$2" force="${3:-}"
  local interval=$((fps * 2))  # default

  case "$mode" in
    low)
      interval=$fps
      ;;
    ultra)
      interval=$((fps / 2))
      ((interval < 1)) && interval=1
      ;;
    ultra_plus)
      interval=$((fps / 4))
      ((interval < 2)) && interval=2
      ;;
  esac

  if [[ -n "$force" ]]; then
    interval="$force"
  fi

  echo "$interval"
}

echo "==> Testing latency mode calculations"

# Test with FPS=24 (common default)
test_case "FPS=24, mode=low → 24"        "24" "$(calculate_keyframe_interval 24 low)"
test_case "FPS=24, mode=ultra → 12"      "12" "$(calculate_keyframe_interval 24 ultra)"
test_case "FPS=24, mode=ultra_plus → 6"   "6" "$(calculate_keyframe_interval 24 ultra_plus)"
test_case "FPS=24, mode=default → 48"    "48" "$(calculate_keyframe_interval 24 "")"

# Test with FPS=30
test_case "FPS=30, mode=low → 30"        "30" "$(calculate_keyframe_interval 30 low)"
test_case "FPS=30, mode=ultra → 15"      "15" "$(calculate_keyframe_interval 30 ultra)"
test_case "FPS=30, mode=ultra_plus → 7"   "7" "$(calculate_keyframe_interval 30 ultra_plus)"

# Test edge cases with low FPS
test_case "FPS=4, mode=ultra → 2"         "2" "$(calculate_keyframe_interval 4 ultra)"
test_case "FPS=2, mode=ultra → 1"         "1" "$(calculate_keyframe_interval 2 ultra)"
test_case "FPS=1, mode=ultra → 1 (min)"   "1" "$(calculate_keyframe_interval 1 ultra)"
test_case "FPS=4, mode=ultra_plus → 2 (min)" "2" "$(calculate_keyframe_interval 4 ultra_plus)"
test_case "FPS=2, mode=ultra_plus → 2 (min)" "2" "$(calculate_keyframe_interval 2 ultra_plus)"

# Test force override
test_case "FPS=24, force=8 overrides"     "8" "$(calculate_keyframe_interval 24 ultra_plus 8)"
test_case "FPS=24, force=1 overrides"     "1" "$(calculate_keyframe_interval 24 low 1)"

echo ""
echo "==> Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
