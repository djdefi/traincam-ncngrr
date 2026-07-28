#!/usr/bin/env bash
# Test viewer.html.j2 recovers from a failed WHEP connect and ignores stale peers.
# The fair runs unattended: any connect path that throws without scheduling a
# reconnect leaves a permanent black screen.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/ansible/roles/traincam/templates/viewer.html.j2"

echo "==> Testing viewer reconnect behaviour"

if ! command -v node >/dev/null 2>&1; then
  echo "! node not installed, skipping viewer JS tests"
  exit 0
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Render the template's script block: strip HTML, substitute the one Jinja expression.
sed -n '/^<script>/,/^<\/script>/p' "$TEMPLATE" \
  | sed -e '1d' -e '$d' -e 's/{{[^}]*}}/8889/g' > "$TEMP_DIR/viewer.js"

if [[ ! -s "$TEMP_DIR/viewer.js" ]]; then
  echo "✗ could not extract script block from $TEMPLATE"
  exit 1
fi

cat > "$TEMP_DIR/harness.js" <<'HARNESS'
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

let reconnects = 0;
const peers = [];

class FakePC {
  constructor() { this.handlers = {}; this.connectionState = 'new'; peers.push(this); }
  addEventListener(type, fn) { (this.handlers[type] ||= []).push(fn); }
  addTransceiver() {}
  close() { this.closed = true; }
  createOffer() { return FakePC.failOffer ? Promise.reject(new Error('createOffer boom')) : Promise.resolve({ sdp: 'v=0' }); }
  setLocalDescription() { return Promise.resolve(); }
  setRemoteDescription() { return Promise.resolve(); }
  fire(type, state) { if (state) this.connectionState = state; (this.handlers[type] || []).forEach(fn => fn()); }
}

const els = {};
const makeEl = () => ({
  textContent: '', disabled: false, checked: true, srcObject: null, style: {},
  classList: { add() {}, remove() {} }, addEventListener() {},
  requestFullscreen: () => Promise.resolve(),
});

globalThis.document = {
  getElementById: id => (els[id] ||= makeEl()),
  body: { classList: { add() {}, remove() {} } },
};
globalThis.window = { location: { href: 'http://traincam1.local:8080/viewer.html' }, addEventListener() {} };
globalThis.RTCPeerConnection = FakePC;
globalThis.fetch = () => Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve('v=0') });
globalThis.console = { log() {} };
let pendingReconnect = null;
globalThis.setTimeout = (fn, ms) => { if (ms === 1500) { reconnects++; pendingReconnect = fn; } return { ms }; };
globalThis.clearTimeout = () => {};
const flush = async () => { for (let i = 0; i < 4; i++) await new Promise(r => setImmediate(r)); };

vm.runInThisContext(fs.readFileSync(process.argv[2], 'utf8'));

(async () => {
  // 1. A rejection from createOffer (previously an unhandled promise rejection)
  //    must clean up and schedule a reconnect rather than hanging forever.
  FakePC.failOffer = true;
  await connect();
  assert.strictEqual(reconnects, 1, 'failed connect should schedule exactly one reconnect');
  assert.strictEqual(peers[0].closed, true, 'failed connect should close its peer');
  assert.strictEqual(els.connectBtn.disabled, false, 'failed connect should re-enable Connect');
  process.stdout.write('✓ connect() rejection schedules a reconnect\n');

  // 2. A late event from the discarded peer must not tear down or double-reconnect.
  peers[0].fire('connectionstatechange', 'failed');
  assert.strictEqual(reconnects, 1, 'stale peer event should not schedule another reconnect');
  process.stdout.write('✓ stale peer event is ignored\n');

  // 3. The scheduled reconnect actually reconnects, and that peer's own failure
  //    schedules the next one — i.e. the retry loop keeps running unattended.
  FakePC.failOffer = false;
  pendingReconnect();
  await flush();
  assert.strictEqual(peers.length, 2, 'reconnect should create a new peer');
  assert.strictEqual(els.disconnectBtn.disabled, false, 'successful connect enables Disconnect');
  peers[1].fire('connectionstatechange', 'failed');
  assert.strictEqual(reconnects, 2, 'live peer failure should schedule a reconnect');
  process.stdout.write('✓ reconnect loop keeps retrying\n');
})().catch(err => { process.stdout.write('✗ ' + err.message + '\n'); process.exit(1); });
HARNESS

if node "$TEMP_DIR/harness.js" "$TEMP_DIR/viewer.js"; then
  echo "==> viewer reconnect tests passed"
  exit 0
else
  echo "==> viewer reconnect tests FAILED"
  exit 1
fi
