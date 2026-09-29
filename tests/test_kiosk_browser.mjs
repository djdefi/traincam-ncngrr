// Run with CHROME=/path/to/chromium node tests/test_kiosk_browser.mjs.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

const root = path.resolve(import.meta.dirname, '..');
const chrome = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
assert(fs.existsSync(chrome), 'Set CHROME to an installed Chromium executable');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'traincam-browser-'));
const children = [], sockets = [], logs = [];
function start(command, args) {
  const log = fs.openSync(path.join(dir, `child-${children.length}.log`), 'w');
  logs.push(log);
  const child = spawn(command, args, { stdio: ['ignore', log, log] });
  children.push(child);
  return child;
}
async function json(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(2000) });
  assert(response.ok, `${url}: ${response.status}`);
  return response.json();
}
async function until(fn, description, seconds = 40) {
  const deadline = Date.now() + seconds * 1000;
  let last;
  while (Date.now() < deadline) {
    try { if (await fn()) return; } catch (error) { last = error; }
    await sleep(500);
  }
  throw new Error(`Timed out: ${description}`, { cause: last });
}
async function cdp(port) {
  const pages = await json(`http://127.0.0.1:${port}/json/list`);
  const socket = new WebSocket(pages.find(page => page.type === 'page').webSocketDebuggerUrl);
  sockets.push(socket);
  await once(socket, 'open');
  let id = 0;
  const pending = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (pending.has(message.id)) {
      const { resolve, reject, timer } = pending.get(message.id);
      pending.delete(message.id);
      clearTimeout(timer);
      if (message.error) reject(new Error(JSON.stringify(message.error)));
      else resolve(message.result);
    }
  });
  return (method, params = {}) => new Promise((resolve, reject) => {
    const key = ++id;
    const timer = setTimeout(() => { pending.delete(key); reject(new Error(`CDP timeout: ${method}`)); }, 5000);
    pending.set(key, { resolve, reject, timer });
    socket.send(JSON.stringify({ id:key, method, params }));
  });
}

try {
  const site = path.join(dir, 'site');
  fs.mkdirSync(site);
  fs.cpSync(path.join(root, 'ansible/roles/trainview/files/visitor'), path.join(site, 'visitor'), { recursive:true });
  const vars = { trainview_camera:'127.0.0.1', trainview_esp32_camera:'127.0.0.1',
    trainview_whep_port:'18083', trainview_esp32_relay_port:'18083', trainview_usb_relay_port:'18083',
    WHEP_PORT:'18083' };
  for (const [template, name] of [
    ['ansible/roles/trainview/templates/kiosk.html.j2', 'kiosk.html'],
    ['ansible/roles/traincam/templates/viewer.html.j2', 'viewer.html'],
  ]) {
    const source = fs.readFileSync(path.join(root, template), 'utf8').replace(/\{\{([^}]+)\}\}/g,
      (_, variable) => vars[variable.trim()] ?? '18083');
    fs.writeFileSync(path.join(site, name), source);
  }
  start('python3', [path.join(root, 'ansible/roles/trainview/files/kiosk-server.py'),
    '--directory', site, '--port', '18081']);
  // A real multipart stream with a controllable stale-frame status endpoint.
  start('python3', ['-u', '-c', `
import json, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
photo = Path(sys.argv[1]).read_bytes()
state = {"live": True}
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path.startswith("/control/"):
   state["live"] = self.path.endswith("live")
   self.send_response(200); self.end_headers(); self.wfile.write(b"{}"); return
  if self.path.startswith("/status"):
   payload = json.dumps({"uptime_s":int(time.monotonic()),"frame_sequence":int(time.monotonic()*10),
    "frame_age_ms":0 if state["live"] else 9000}).encode()
   self.send_response(200); self.send_header("Access-Control-Allow-Origin","*")
   self.send_header("Content-Length",str(len(payload))); self.end_headers(); self.wfile.write(payload); return
  if self.path.startswith("/stream"):
   self.send_response(200); self.send_header("Access-Control-Allow-Origin","*")
   self.send_header("Content-Type","multipart/x-mixed-replace; boundary=frame"); self.end_headers()
   try:
    while True:
     if state["live"]:
      self.wfile.write(b"--frame\\r\\nContent-Type: image/jpeg\\r\\nContent-Length: "+str(len(photo)).encode()+b"\\r\\n\\r\\n"+photo+b"\\r\\n")
      self.wfile.flush()
     time.sleep(.1)
   except (BrokenPipeError,ConnectionResetError): pass
   return
  self.send_error(404)
 def do_POST(self):
  time.sleep(20)
  self.send_error(503)
 def log_message(self,*args): pass
ThreadingHTTPServer(("127.0.0.1",18083),Handler).serve_forever()
`, path.join(site, 'visitor/layout.jpg')]);
  await until(() => json('http://127.0.0.1:18081/_kiosk/health'), 'local server');
  await until(() => json('http://127.0.0.1:18083/status'), 'MJPEG fixture');
  for (const [output, port] of [['1',19221], ['usb',19222]]) {
    start(chrome, ['--headless', '--no-first-run', '--no-default-browser-check',
      '--disable-background-networking', '--disable-extensions', '--autoplay-policy=no-user-gesture-required',
      '--window-size=1920,1080', `--user-data-dir=${path.join(dir, output)}`,
      `--remote-debugging-port=${port}`, '--remote-debugging-address=127.0.0.1',
      `http://127.0.0.1:18081/kiosk.html?output=${output}`]);
  }
  await until(() => json('http://127.0.0.1:19222/json/list'), 'Chromium');
  const usb = await cdp(19222), first = await cdp(19221);
  async function selected(client) {
    return (await client('Runtime.evaluate', { expression:'selected', returnByValue:true })).result.value;
  }
  await until(async () => await selected(usb) === 'usb', 'USB first frame and stable recovery');
  const cameraLayout = await usb('Runtime.evaluate', { expression:`(() => {
    const f = document.querySelector('#usb iframe');
    const r = f.getBoundingClientRect(), d = f.contentDocument, w = f.contentWindow;
    return { left:r.left / innerWidth, top:r.top / innerHeight,
      fit:w.getComputedStyle(d.getElementById('mjpeg')).objectFit,
      badge:parseFloat(w.getComputedStyle(d.getElementById('health')).fontSize) };
  })()`, returnByValue:true });
  assert(cameraLayout.result.value.left >= .049 && cameraLayout.result.value.top >= .049);
  assert.equal(cameraLayout.result.value.fit, 'contain');
  assert(cameraLayout.result.value.badge >= 24);
  console.log('PASS: real MJPEG frames select the USB camera');
  await json('http://127.0.0.1:18083/control/stale');
  await until(async () => await selected(usb) === 'visitor', 'stale MJPEG fallback', 15);
  console.log('PASS: HTTP 200 with stale frames falls back to offline visitor display');
  await json('http://127.0.0.1:18083/control/live');
  await until(async () => await selected(usb) === 'usb', 'MJPEG resumes after stale stream');
  console.log('PASS: USB automatically returns after frames resume');
  // No remote stream is healthy even though HTTP and page scripts are running.
  await json('http://127.0.0.1:18083/control/stale');
  await until(async () => await selected(first) === 'visitor', 'first display visitor fallback', 15);
  const health = await json('http://127.0.0.1:18081/_kiosk/health');
  assert(Object.values(health.heartbeat_age_s).every(age => age !== null && age < 15));
  const screenshot = await first('Page.captureScreenshot', { format:'png' });
  if (process.env.KIOSK_SCREENSHOT) fs.writeFileSync(process.env.KIOSK_SCREENSHOT, Buffer.from(screenshot.data, 'base64'));
  const layout = await first('Runtime.evaluate', { expression:`(() => {
    const d = document.querySelector('#visitor iframe').contentDocument;
    return { overflow:d.documentElement.scrollHeight > d.defaultView.innerHeight,
      images:[...d.images].every(image => image.complete && image.naturalWidth > 0) };
  })()`, returnByValue:true });
  assert.equal(layout.result.value.overflow, false);
  assert.equal(layout.result.value.images, true);
  for (const [width, height] of [[1920,1080], [1280,720], [640,480]]) {
    await first('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor:1, mobile:false });
    for (let i = 0; i < 4; i++) {
      const result = await first('Runtime.evaluate', { expression:`(() => {
        const w = document.querySelector('#visitor iframe').contentWindow;
        w.eval('index = ${i}; showSlide()');
        return w.document.documentElement.scrollHeight <= w.innerHeight;
      })()`, returnByValue:true });
      assert.equal(result.result.value, true, `visitor slide ${i} overflows at ${width}x${height}`);
    }
  }
  console.log('PASS: offline visitor assets load without overflow and both pages heartbeat');
} catch (error) {
  for (let i = 0; i < children.length; i++) console.error(fs.readFileSync(path.join(dir, `child-${i}.log`), 'utf8').slice(-4000));
  throw error;
} finally {
  for (const socket of sockets) socket.close();
  for (const child of children.reverse()) {
    if (child.exitCode !== null) continue;
    const exited = once(child, 'exit');
    child.kill('SIGTERM');
    await Promise.race([exited, sleep(3000)]);
    if (child.exitCode === null) { child.kill('SIGKILL'); await exited; }
  }
  for (const log of logs) fs.closeSync(log);
  fs.rmSync(dir, { recursive:true });
}
