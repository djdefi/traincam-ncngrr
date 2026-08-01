#!/usr/bin/env bash
# Guards how the viewer decides where MediaMTX lives.
#
# This is load-bearing for the kiosk. scripts/setup-kiosk.sh serves a cached
# copy of the viewer from the kiosk's own localhost so that an absent camera
# leaves a retrying page instead of a Chromium error page that never retries.
# In that arrangement window.location points at the KIOSK, so the viewer must
# honour an explicit ?whepBase= or it will look for the camera on localhost
# and never connect. That exact bug shipped once already.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$REPO_ROOT/ansible/roles/traincam/templates/viewer.html.j2"

fail=0
check() {
  if [ "$2" = "0" ]; then echo "  PASS: $1"; else echo "  FAIL: $1"; fail=1; fi
}

echo "viewer WHEP base resolution"

[ -f "$TPL" ]; check "template exists" $?

if ! command -v node >/dev/null 2>&1; then
  echo "  SKIP: node not available"; exit 0
fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# Render the template's only Jinja expression, pull out the MTX_BASE
# definition, and exercise it against stubbed page locations.
python3 - "$TPL" "$work/base.js" <<'PY' || { echo "  FAIL: could not extract MTX_BASE"; exit 1; }
import re,sys
src=open(sys.argv[1]).read()
src=re.sub(r"\{\{\s*traincam_webrtc_port\s*\|\s*default\(8889\)\s*\}\}","8889",src)
m=re.search(r"const MTX_BASE = \(\(\) => \{.*?\}\)\(\);", src, re.S)
if not m: sys.exit(1)
open(sys.argv[2],"w").write(m.group(0))
PY

cat >"$work/run.js" <<'EOF'
const fs = require('fs');
const body = fs.readFileSync(process.argv[2], 'utf8');
function resolve(href) {
  const window = { location: { href, origin: new URL(href).origin, search: new URL(href).search } };
  return eval(`${body}; MTX_BASE`);
}
const cases = [
  // served by the camera itself -> port swap on the same host
  ['http://traincam1.local:8080/viewer.html', 'http://traincam1.local:8889'],
  // served by the kiosk from localhost -> explicit base must win
  ['http://localhost:8081/viewer.html?whepBase=http://traincam1.local:8889', 'http://traincam1.local:8889'],
  ['http://localhost:8081/viewer.html?whepBase=http://192.168.0.102:8889', 'http://192.168.0.102:8889'],
  // host override
  ['http://localhost:8081/viewer.html?whepHost=192.168.0.102', 'http://192.168.0.102:8889'],
  // garbage base must not throw; falls back to derived
  ['http://traincam1.local:8080/viewer.html?whepBase=not-a-url', 'http://traincam1.local:8889'],
];
let bad = 0;
for (const [href, want] of cases) {
  let got;
  try { got = resolve(href); } catch (e) { got = 'THREW: ' + e.message; }
  if (got !== want) { console.log(`  MISMATCH ${href}\n    want ${want}\n    got  ${got}`); bad++; }
}
process.exit(bad ? 1 : 0);
EOF

node "$work/run.js" "$work/base.js"; check "resolves camera-served, kiosk-served and override cases" $?

grep -q "whepBase" "$TPL"; check "template still honours whepBase" $?
grep -q "srcObject = null" "$TPL"; check "clears the last frame on cleanup" $?
grep -q "STALL_MS" "$TPL"; check "has a media stall watchdog" $?

echo ""
[ "$fail" = "0" ] && echo "viewer WHEP base: all passed" || echo "viewer WHEP base: FAILURES"
exit "$fail"
