#!/usr/bin/env bash
# Test the network watchdog logic in netwatch.sh.j2
#
# The point of this script is that it reboots an unattended device, so the
# thing worth testing is that it reboots when it should and - more important -
# that it cannot boot-loop when a reboot does not fix the problem.
set -uo pipefail

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "✓ $name"
    PASS=$((PASS + 1))
  else
    echo "✗ $name: expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../ansible/roles/traincam/templates/netwatch.sh.j2"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "✗ template not found: $TEMPLATE"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Render the Jinja vars the same way the role does.
sed -e 's/{{ traincam_netwatch_threshold }}/3/g' \
    -e 's/{{ traincam_netwatch_interval_sec }}/30/g' \
    "$TEMPLATE" >"$TMP/netwatch.sh"
chmod +x "$TMP/netwatch.sh"

if grep -q '{{' "$TMP/netwatch.sh"; then
  echo "✗ unrendered Jinja left in template:"
  grep -n '{{' "$TMP/netwatch.sh"
  FAIL=$((FAIL + 1))
fi

cat >"$TMP/fake-reboot" <<EOF
#!/usr/bin/env bash
echo "reboot" >>"$TMP/reboots"
EOF
chmod +x "$TMP/fake-reboot"

cat >"$TMP/fake-log" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$TMP/log"
EOF
chmod +x "$TMP/fake-log"

STATE="$TMP/state"

run() {
  # $1 = "up" or "down"
  local probe="true"
  [[ "$1" == "down" ]] && probe="false"
  TRAINCAM_NETWATCH_STATE="$STATE" \
  TRAINCAM_NETWATCH_PROBE_CMD="$probe" \
  TRAINCAM_NETWATCH_REBOOT_CMD="$TMP/fake-reboot" \
  TRAINCAM_NETWATCH_LOG_CMD="$TMP/fake-log" \
    bash "$TMP/netwatch.sh"
}

reboots() { [[ -f "$TMP/reboots" ]] && wc -l <"$TMP/reboots" | tr -d ' ' || echo 0; }
fails()   { cat "$STATE/netwatch.fails" 2>/dev/null || echo "none"; }

# --- healthy network does nothing ---
run up
check "healthy: no reboot" "0" "$(reboots)"
check "healthy: no fail counter" "none" "$(fails)"

# --- failures below the threshold only count ---
run down
check "1 failure: counter is 1" "1" "$(fails)"
check "1 failure: no reboot yet" "0" "$(reboots)"
run down
check "2 failures: counter is 2" "2" "$(fails)"
check "2 failures: no reboot yet" "0" "$(reboots)"

# --- recovery clears the counter ---
run up
check "recovered: counter cleared" "none" "$(fails)"

# --- sustained failure reaches the threshold and reboots ---
run down; run down; run down
check "threshold reached: rebooted once" "1" "$(reboots)"
check "threshold reached: counter reset" "none" "$(fails)"
check "threshold reached: stamp written" "yes" \
  "$([[ -f "$STATE/netwatch.rebooted" ]] && echo yes || echo no)"

# --- the important one: a reboot that did not help must NOT loop ---
run down; run down; run down
check "reboot did not help: still only one reboot" "1" "$(reboots)"
check "reboot did not help: says so in the log" "yes" \
  "$(grep -q "STILL unreachable" "$TMP/log" && echo yes || echo no)"

# and it must keep not rebooting, forever
run down; run down; run down
run down; run down; run down
check "never boot-loops" "1" "$(reboots)"

# --- once the network genuinely returns, the stamp clears ---
run up
check "recovered: stamp cleared" "no" \
  "$([[ -f "$STATE/netwatch.rebooted" ]] && echo yes || echo no)"

# --- so a later, separate outage is allowed to reboot again ---
run down; run down; run down
check "new outage after recovery: reboots again" "2" "$(reboots)"

# --- a corrupt counter must not wedge the watchdog ---
rm -rf "$STATE"; rm -f "$TMP/reboots"
mkdir -p "$STATE"
echo "garbage" >"$STATE/netwatch.fails"
run down
check "corrupt counter treated as zero" "1" "$(fails)"

# --- no default route must count as a failure, not a free pass ---
rm -rf "$STATE"
TRAINCAM_NETWATCH_STATE="$STATE" \
TRAINCAM_NETWATCH_PROBE_CMD="false" \
TRAINCAM_NETWATCH_REBOOT_CMD="$TMP/fake-reboot" \
TRAINCAM_NETWATCH_LOG_CMD="$TMP/fake-log" \
  bash "$TMP/netwatch.sh"
check "probe failure counts" "1" "$(fails)"

echo ""
echo "Passed: $PASS, Failed: $FAIL"
[[ $FAIL -eq 0 ]]
