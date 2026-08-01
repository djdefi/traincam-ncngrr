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
  if grep -q "webrtcAddress.*traincam_webrtc_port" "$MEDIAMTX_TEMPLATE"; then
    test_case "MediaMTX WebRTC port is configured" "found" "found"
  else
    test_case "MediaMTX WebRTC port is configured" "found" "missing"
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
  # Credentials must NOT be hardcoded here. This repo is public, and the old
  # plaintext WiFi password is still in git history because it was (806f855).
  # This assertion used to require the SSID be hardcoded, which enforced the
  # leak rather than catching it.
  if grep -qE '(ssid|password) *= *"' "$ESP32_INO"; then
    test_case "ESP32 credentials not hardcoded" "clean" "hardcoded credential found"
  else
    test_case "ESP32 credentials not hardcoded" "clean" "clean"
  fi

  if grep -q '#include "secrets.h"' "$ESP32_INO"; then
    test_case "ESP32 reads credentials from secrets.h" "found" "found"
  else
    test_case "ESP32 reads credentials from secrets.h" "found" "missing"
  fi

  # The gitignore entry is the actual protection; without it secrets.h gets
  # committed silently the next time someone runs `git add -A`.
  if grep -q '^CameraWebServer/secrets.h$' .gitignore 2>/dev/null; then
    test_case "secrets.h is gitignored" "found" "found"
  else
    test_case "secrets.h is gitignored" "found" "missing"
  fi
  # Check WiFi.setSleep(false) for reliable streaming
  if grep -q 'WiFi.setSleep(false)' "$ESP32_INO"; then
    test_case "ESP32 WiFi sleep disabled" "found" "found"
  else
    test_case "ESP32 WiFi sleep disabled" "found" "missing"
  fi

  if grep -q 'MDNS.addService("traincam", "tcp", 80)' "$ESP32_INO"; then
    test_case "ESP32 advertises TrainCam mDNS service" "found" "found"
  else
    test_case "ESP32 advertises TrainCam mDNS service" "found" "missing"
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

  AVAHI_TEMPLATE="ansible/roles/traincam/templates/traincam-avahi.service.j2"
  if grep -q "_traincam._tcp" "$AVAHI_TEMPLATE"; then
    test_case "Pi advertises TrainCam mDNS service" "found" "found"
  else
    test_case "Pi advertises TrainCam mDNS service" "found" "missing"
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
  if grep -Fq '/${PATH}/whep' "$VIEWER"; then
    test_case "Viewer uses MediaMTX WHEP path" "found" "found"
  else
    test_case "Viewer uses MediaMTX WHEP path" "found" "missing"
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

  if grep -q 'Requires=mediamtx.service' "$SERVICE_TEMPLATE"; then
    test_case "traincam.service requires mediamtx" "found" "found"
  else
    test_case "traincam.service requires mediamtx" "found" "missing"
  fi
else
  skip_case "Service dependency check" "file not found"
fi

VIEWER_SERVER="ansible/roles/traincam/files/viewer_server.py"
if python3 -m py_compile "$VIEWER_SERVER"; then
  test_case "Viewer server compiles" "ok" "ok"
else
  test_case "Viewer server compiles" "ok" "failed"
fi
STATUS_SCHEMA=$(python3 - "$VIEWER_SERVER" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("viewer_server", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
required = {"hostname", "uptime_s", "temperature_c", "ip", "type", "stream"}
print("ok" if required <= module.get_status().keys() else "missing")
PY
)
test_case "Viewer status schema is complete" "ok" "$STATUS_SCHEMA"

echo ""
echo "--- Headless Power Configuration ---"

TRAINCAM_TASKS="ansible/roles/traincam/tasks/main.yml"
if grep -q '/lib/systemd/system/multi-user.target' "$TRAINCAM_TASKS"; then
  test_case "Camera Pi boots headless" "found" "found"
else
  test_case "Camera Pi boots headless" "found" "missing"
fi

HEADLESS_SETTINGS=$(grep -Ec "line: '(dtparam=audio=off|dtparam=hdmi=off|enable_tvout=0|dtoverlay=disable-bt)'" "$TRAINCAM_TASKS")
test_case "Unused headless hardware is disabled" "4" "$HEADLESS_SETTINGS"

if grep -A4 'Remove obsolete NetworkManager override' "$TRAINCAM_TASKS" | grep -q 'state: absent'; then
  test_case "Invalid NetworkManager override is removed" "found" "found"
else
  test_case "Invalid NetworkManager override is removed" "found" "missing"
fi

echo ""
echo "==> Results: $PASS passed, $FAIL failed, $SKIP skipped"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
