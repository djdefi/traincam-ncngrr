#!/usr/bin/env bash
# Test white balance argument selection in publish.sh.j2.
#
# Auto white balance converges differently in the video pipeline than in the
# still one (measured: stills [0.989, 2.230], video [0.863, 2.037] on the same
# scene), which shows up as a green cast in the actual stream. AWB_GAINS locks
# it. Getting the branch wrong either drops the correction silently or passes
# both flags, so this renders the real template and runs it rather than
# re-implementing the logic here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/ansible/roles/traincam/templates/publish.sh.j2"

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

echo "==> Testing white balance argument selection"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/conf" "$TEMP_DIR/bin"

# Render the Jinja placeholders this template actually uses.
sed -e "s#{{ traincam_config_dir }}#$TEMP_DIR/conf#g" \
    -e "s#{{ traincam_width }}#1280#g" \
    -e "s#{{ traincam_height }}#720#g" \
    -e "s#{{ traincam_fps }}#24#g" \
    -e "s#{{ traincam_awb }}#auto#g" \
    -e "s#{{ traincam_awb_gains | default('') }}##g" \
    -e "s#{{ traincam_tuning_file | default('') }}##g" \
    -e "s#{{ traincam_extra_opts }}##g" \
    "$TEMPLATE" > "$TEMP_DIR/publish.sh"
chmod +x "$TEMP_DIR/publish.sh"

if grep -q '{{' "$TEMP_DIR/publish.sh"; then
  echo "! unrendered Jinja left in template, this test needs updating:"
  grep -n '{{' "$TEMP_DIR/publish.sh"
  exit 1
fi

# Stubs: capture the camera argv, and swallow the pipe so nothing blocks.
cat > "$TEMP_DIR/bin/rpicam-vid" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$TEMP_DIR/argv"
EOF
cat > "$TEMP_DIR/bin/ffmpeg" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
EOF
chmod +x "$TEMP_DIR/bin/rpicam-vid" "$TEMP_DIR/bin/ffmpeg"

run_with() {
  printf '%s\n' "$@" > "$TEMP_DIR/conf/stream.conf"
  rm -f "$TEMP_DIR/argv"
  PATH="$TEMP_DIR/bin:$PATH" "$TEMP_DIR/publish.sh" >/dev/null 2>&1
  tr '\n' ' ' < "$TEMP_DIR/argv"
}

# Locked gains: --awbgains is passed and --awb is not, or rpicam-vid gets
# contradictory instructions.
argv=$(run_with 'AWB="auto"' 'AWB_GAINS="0.99,2.23"')
test_case "locked gains pass --awbgains" "yes" \
  "$([[ "$argv" == *"--awbgains 0.99,2.23 "* ]] && echo yes || echo no)"
test_case "locked gains omit --awb"      "yes" \
  "$([[ "$argv" != *"--awb "* ]] && echo yes || echo no)"

# Empty gains must fall back to auto, so clearing the variable is a safe revert.
argv=$(run_with 'AWB="auto"' 'AWB_GAINS=""')
test_case "empty gains fall back to --awb" "yes" \
  "$([[ "$argv" == *"--awb auto "* ]] && echo yes || echo no)"
test_case "empty gains omit --awbgains"    "yes" \
  "$([[ "$argv" != *"--awbgains"* ]] && echo yes || echo no)"

# An unset variable must behave like an empty one - stream.conf is Ansible
# managed and an older one on disk will not define AWB_GAINS at all.
argv=$(run_with 'AWB="incandescent"')
test_case "unset gains fall back to --awb" "yes" \
  "$([[ "$argv" == *"--awb incandescent "* ]] && echo yes || echo no)"

echo ""
echo "==> Results: $PASS passed, $FAIL failed"
[[ $FAIL -gt 0 ]] && exit 1
exit 0
