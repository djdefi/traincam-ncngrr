#!/usr/bin/env bash
# Test network/port requirements and configuration
set -uo pipefail

echo "==> Network Configuration Tests"
echo ""

PASS=0
FAIL=0
SKIP=0

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

skip_case() {
  local name="$1" reason="$2"
  echo "○ $name (skipped: $reason)"
  SKIP=$((SKIP + 1))
}

# Test 1: Check expected ports in configuration
echo "--- Port Configuration ---"

# Check mediamtx.yml.j2 for RTSP path
MEDIAMTX_TEMPLATE="ansible/roles/traincam/templates/mediamtx.yml.j2"
if [[ -f "$MEDIAMTX_TEMPLATE" ]]; then
  if grep -q "traincam:" "$MEDIAMTX_TEMPLATE"; then
    test_case "MediaMTX has 'traincam' path defined" "found" "found"
  else
    test_case "MediaMTX has 'traincam' path defined" "found" "missing"
  fi
else
  skip_case "MediaMTX template exists" "file not found"
fi

# Check group_vars for port config
GROUP_VARS="group_vars/traincam.yml"
if [[ -f "$GROUP_VARS" ]]; then
  PORT=$(grep "traincam_port:" "$GROUP_VARS" | awk '{print $2}' || echo "")
  test_case "RTSP port configured" "8554" "$PORT"
else
  skip_case "Group vars port check" "file not found"
fi

echo ""
echo "--- WiFi Configuration ---"

# Check ESP32 firmware for WiFi settings
ESP32_INO="CameraWebServer/CameraWebServer.ino"
if [[ -f "$ESP32_INO" ]]; then
  SSID=$(grep 'ssid = ' "$ESP32_INO" | grep -o '"[^"]*"' | tr -d '"' | head -1 || echo "")
  test_case "ESP32 SSID is 'traincameranet'" "traincameranet" "$SSID"
  
  # Check WiFi.setSleep(false) for reliable streaming
  if grep -q 'WiFi.setSleep(false)' "$ESP32_INO"; then
    test_case "ESP32 WiFi sleep disabled" "found" "found"
  else
    test_case "ESP32 WiFi sleep disabled" "found" "missing"
  fi
else
  skip_case "ESP32 WiFi config" "file not found"
fi

echo ""
echo "--- mDNS/Discovery ---"

# Check inventory for .local hostname usage
INVENTORY="inventory"
if [[ -f "$INVENTORY" ]]; then
  if grep -q '\.local' "$INVENTORY"; then
    test_case "Inventory uses mDNS hostnames" "found" "found"
  else
    test_case "Inventory uses mDNS hostnames" "found" "missing"
  fi
else
  skip_case "Inventory mDNS check" "file not found"
fi

# Check if viewer.html uses .local hostnames
VIEWER="client/viewer.html"
if [[ -f "$VIEWER" ]]; then
  # The viewer uses location.hostname by default, with optional overrides
  if grep -q "whepBase" "$VIEWER"; then
    test_case "Viewer supports WHEP base override" "found" "found"
  else
    test_case "Viewer supports WHEP base override" "found" "missing"
  fi
else
  skip_case "Viewer hostname check" "file not found"
fi

echo ""
echo "--- Service Dependencies ---"

# Check traincam.service depends on network
SERVICE_TEMPLATE="ansible/roles/traincam/templates/traincam.service.j2"
if [[ -f "$SERVICE_TEMPLATE" ]]; then
  if grep -q 'network-online.target' "$SERVICE_TEMPLATE"; then
    test_case "traincam.service waits for network" "found" "found"
  else
    test_case "traincam.service waits for network" "found" "missing"
  fi
  
  if grep -q 'After=mediamtx.service' "$SERVICE_TEMPLATE"; then
    test_case "traincam.service starts after mediamtx" "found" "found"
  else
    test_case "traincam.service starts after mediamtx" "found" "missing"
  fi
else
  skip_case "Service dependency check" "file not found"
fi

echo ""
echo "==> Results: $PASS passed, $FAIL failed, $SKIP skipped"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
