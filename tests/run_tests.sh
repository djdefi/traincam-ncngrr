#!/usr/bin/env bash
# Run all traincam tests
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

TOTAL_PASS=0
TOTAL_FAIL=0

run_test() {
  local test_file="$1"
  local name
  name=$(basename "$test_file" .sh)
  
  echo ""
  echo "========================================"
  echo "Running: $name"
  echo "========================================"
  
  if bash "$test_file"; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
}

echo "TrainCam Test Suite"
echo "==================="

# Run all test files
for test_file in "$SCRIPT_DIR"/test_*.sh; do
  if [[ -f "$test_file" && "$test_file" != *"run_tests.sh"* ]]; then
    run_test "$test_file"
  fi
done

echo ""
echo "========================================"
echo "Summary: $TOTAL_PASS test files passed, $TOTAL_FAIL failed"
echo "========================================"

if [[ $TOTAL_FAIL -gt 0 ]]; then
  exit 1
fi
