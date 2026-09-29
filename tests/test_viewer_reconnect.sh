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
  | sed -e '1d' -e '$d' \
        -e 's/{{ traincam_viewer_port[^}]*}}/8080/g' \
        -e 's/{{ traincam_webrtc_port[^}]*}}/8889/g' \
        -e 's/{{[^}]*}}/8889/g' > "$TEMP_DIR/viewer.js"

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
const winHandlers = {};

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
  textContent: '', disabled: false, checked: true, srcObject: null, style: {}, hidden: false,
  classList: { add() {}, remove() {}, toggle() {} },
  handlers: {},
  addEventListener(type, fn) { (this.handlers[type] ||= []).push(fn); },
  fire(type) { (this.handlers[type] || []).forEach(fn => fn()); },
  requestFullscreen: () => Promise.resolve(),
});

globalThis.document = {
  getElementById: id => (els[id] ||= makeEl()),
  body: { classList: { add() {}, remove() {} } },
};
globalThis.window = {
  location: { href: 'http://traincam1.local:8080/viewer.html' },
  addEventListener(type, fn) { (winHandlers[type] ||= []).push(fn); },
};
globalThis.RTCPeerConnection = FakePC;
// Records every request so the tests can assert the WHEP session is released.
const fetches = [];
globalThis.fetch = (url, opts) => {
  fetches.push({ url, opts: opts || {} });
  return Promise.resolve({
    ok: true, status: 201,
    // MediaMTX returns a RELATIVE Location; the viewer must resolve it
    // against the WHEP origin, not the page origin (different port).
    headers: { get: k => (k.toLowerCase() === 'location' ? '/traincam/whep/abc-123' : null) },
    text: () => Promise.resolve('v=0'),
  });
};
globalThis.console = { log() {} };
let pendingReconnect = null;
// Record every timer. 600 (fullscreen) and 2000 (UI hide) are the only two
// non-reconnect timers in the viewer; everything else is a retry, whose delay
// is now jittered and so cannot be matched by a fixed value.
const delays = [];
globalThis.setTimeout = (fn, ms) => {
  if (ms !== 600 && ms !== 2000 && fn.name !== 'connectionTimeout') { reconnects++; pendingReconnect = fn; delays.push(ms); }
  return { ms };
};
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

  // 4. Every WHEP session must be released with a DELETE. Without this the
  //    server keeps writing to a reader that stopped reading; three stale
  //    sessions were observed at once, one of them for 28 minutes.
  const deletes = fetches.filter(f => (f.opts.method || 'GET').toUpperCase() === 'DELETE');
  assert.ok(deletes.length >= 1, 'cleanup should DELETE the WHEP session');
  assert.strictEqual(
    deletes[0].url, 'http://traincam1.local:8889/traincam/whep/abc-123',
    'relative Location must resolve against the WHEP origin (port 8889), not the page (8080)');
  process.stdout.write('✓ WHEP session is released with a DELETE\n');

  // 5. cleanup() aborts the AbortController, so a DELETE carrying that signal
  //    would cancel itself and silently leak the session anyway.
  assert.ok(deletes.every(d => !d.opts.signal),
    'DELETE must not use the abort signal that cleanup() fires');
  assert.ok(deletes.every(d => d.opts.keepalive === true),
    'DELETE needs keepalive to survive the page being closed');
  process.stdout.write('✓ DELETE survives cleanup and page unload\n');

  // 6. Closing a tab or backgrounding the app on a phone must release too -
  //    the exact thing visitors do all day at the show.
  assert.ok(winHandlers.pagehide && winHandlers.pagehide.length,
    'viewer must handle pagehide or a closed tab strands the session');
  FakePC.failOffer = false;
  await connect();
  await flush();
  const before = fetches.filter(f => (f.opts.method || '').toUpperCase() === 'DELETE').length;
  winHandlers.pagehide.forEach(fn => fn());
  const after = fetches.filter(f => (f.opts.method || '').toUpperCase() === 'DELETE').length;
  assert.strictEqual(after, before + 1, 'pagehide should release exactly one session');
  process.stdout.write('✓ closing the tab releases the session\n');

  // 7. ...and releasing twice must not fire a second DELETE.
  winHandlers.pagehide.forEach(fn => fn());
  const again = fetches.filter(f => (f.opts.method || '').toUpperCase() === 'DELETE').length;
  assert.strictEqual(again, after, 'a second cleanup should not re-DELETE');
  process.stdout.write('✓ double cleanup does not double-DELETE\n');

  // 8. Retries must back off. A fixed 1.5s retry had one tab create 143 WHEP
  //    sessions in 5 minutes (measured 1.57-1.63s apart, one source port)
  //    while the radio was already failing. Pin Math.random mid-range so the
  //    jitter is a no-op and the ladder itself is exact.
  const realRandom = Math.random;
  Math.random = () => 0.5;
  FakePC.failOffer = false;
  await connect(); await flush();
  let live = () => peers[peers.length - 1];
  live().fire('connectionstatechange', 'connected');   // resets the ladder
  delays.length = 0;
  FakePC.failOffer = true;
  live().fire('connectionstatechange', 'failed');      // -> 1500
  for (let i = 0; i < 5; i++) { pendingReconnect(); await flush(); }
  assert.deepStrictEqual(delays.slice(0, 5), [1500, 3000, 6000, 12000, 15000],
    'retries should double and cap at 15s, got ' + JSON.stringify(delays.slice(0, 5)));
  process.stdout.write('✓ retries back off and cap at 15s\n');

  // 9. A successful connect resets the ladder, or one bad patch of track
  //    leaves the viewer retrying every 15s for the rest of the day.
  FakePC.failOffer = false;
  pendingReconnect(); await flush();
  live().fire('connectionstatechange', 'connected');
  delays.length = 0;
  FakePC.failOffer = true;
  live().fire('connectionstatechange', 'failed');
  assert.strictEqual(delays[0], 1500, 'a connected peer should reset the backoff, got ' + delays[0]);
  process.stdout.write('✓ a successful connect resets the backoff\n');

  // 10. The delay must actually depend on Math.random. Without jitter every
  //     phone in the hall retries on the same tick and hits the AP as one.
  FakePC.failOffer = false;
  pendingReconnect(); await flush();
  live().fire('connectionstatechange', 'connected');   // base is 1500 again
  Math.random = () => 0;
  delays.length = 0;
  FakePC.failOffer = true;
  live().fire('connectionstatechange', 'failed');
  Math.random = realRandom;
  assert.strictEqual(delays[0], 1125,
    'retry delay must be jittered by +/-25% of 1500, got ' + delays[0]);
  process.stdout.write('✓ retry delay is jittered\n');

  // 11. The offline card must toggle BOTH ways. Asserting it is visible after a
  //     loss proves nothing on its own - it starts visible - so force the
  //     opposite state before each direction, the same bookending the image
  //     measurements needed.
  const offline = els.offline;
  assert.ok(offline, 'viewer must define an #offline element');
  FakePC.failOffer = false;
  pendingReconnect(); await flush();
  live().fire('connectionstatechange', 'connected');

  //     Frames arriving clear it. Bound to timeupdate, not playing: currentTime
  //     only advances when frames land, so a stream that connects then stalls
  //     correctly keeps the card up.
  offline.hidden = false;
  els.video.fire('timeupdate');
  assert.strictEqual(offline.hidden, true,
    'arriving frames must hide the offline card');
  process.stdout.write('✓ arriving frames hide the offline card\n');

  //     Losing the stream raises it again. Without this the public sees the
  //     black screen cleanup() deliberately creates by dropping srcObject, and
  //     nobody can tell a dead camera from a train that has stopped.
  FakePC.failOffer = true;
  live().fire('connectionstatechange', 'failed');
  assert.strictEqual(offline.hidden, false,
    'losing the stream must re-show the offline card');
  process.stdout.write('✓ losing the stream re-shows the offline card\n');

  // 12. The operational clock must distinguish the camera from this browser.
  //     The kiosk serves a cached viewer from localhost, so derive camera /status
  //     from whepBase rather than window.location.
  assert.strictEqual(CAMERA_STATUS, 'http://traincam1.local:8080/status',
    'camera status must follow the WHEP host, not the kiosk page origin');
  assert.strictEqual(formatDuration(90061), '25:01:01',
    'uptime must not wrap after 24 hours');
  noteCameraStatus({ uptime_s: 123, battery_mv: 3712, temperature_c: 58.4 });
  assert.strictEqual(cameraUptime, 123, 'camera uptime must use the server status value');
  assert.strictEqual(cameraPowerMv, 3712, 'camera power voltage must use status telemetry');
  assert.strictEqual(cameraTemperatureC, 58.4, 'camera temperature must use status telemetry');
  noteCameraStatus({ uptime_s: 124 });
  assert.strictEqual(cameraPowerMv, null, 'missing power telemetry must hide rather than show stale data');
  assert.strictEqual(cameraTemperatureC, null, 'missing temperature telemetry must hide rather than show stale data');
  lastFrameAt = Date.now();
  assert.deepStrictEqual(healthState(Date.now()), ['health-ok', '▶', 'LIVE'],
    'recent frames and a responding camera must read LIVE without relying on color');
  lastFrameAt = 0;
  assert.deepStrictEqual(healthState(Date.now()), ['health-warn', '!', 'NO VIDEO'],
    'a responding camera without frames must identify the video path');
  cameraUptime = null;
  assert.deepStrictEqual(healthState(Date.now()), ['health-dead', '×', 'CAMERA OFFLINE'],
    'an unreachable camera must be explicit without relying on color');
  process.stdout.write('✓ health display separates camera and viewer uptime\n');
})().then(() => process.exit(0)).catch(err => { process.stdout.write('✗ ' + err.message + '\n'); process.exit(1); });
HARNESS

# The card is display:flex, so a bare `[hidden]{display:none}` (specificity 0,1,0)
# would LOSE to `#offline` (1,0,0) and the card would sit over a perfectly good
# picture all day. Only an id-qualified override actually hides it.
if ! grep -qE '#offline\[hidden\][[:space:]]*\{[^}]*display[[:space:]]*:[[:space:]]*none' "$TEMPLATE"; then
  echo "✗ #offline[hidden] must set display:none, or the offline card never hides"
  exit 1
fi
echo "✓ offline card has an id-qualified [hidden] override"

if ! grep -q 'right:4vw; bottom:4vh' "$TEMPLATE" || ! grep -q 'frame_sequence' "$TEMPLATE"; then
  echo "✗ health badge must stay inside overscan and follow MJPEG frame progress"
  exit 1
fi
echo "✓ health badge is overscan-safe and follows MJPEG frames"

if node "$TEMP_DIR/harness.js" "$TEMP_DIR/viewer.js"; then
  echo "==> viewer reconnect tests passed"
  exit 0
else
  echo "==> viewer reconnect tests FAILED"
  exit 1
fi
