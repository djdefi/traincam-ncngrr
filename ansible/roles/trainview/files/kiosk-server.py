#!/usr/bin/env python3
"""Serve the kiosk and recover browsers whose page heartbeats stop."""

import argparse
from collections import deque
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
from pathlib import Path
import subprocess
import threading
import time

OUTPUTS = ("1", "usb")
STARTUP_SECONDS = 180
STALE_SECONDS = 45
RESTART_WINDOW_SECONDS = 900
MAX_RESTARTS = 3


class Health:
    def __init__(self):
        self.lock = threading.Lock()
        self.pid = None
        self.started = time.monotonic()
        self.seen = dict.fromkeys(OUTPUTS)
        self.restarts = deque()
        self.limited = False

    def heartbeat(self, output):
        with self.lock:
            self.seen[output] = time.monotonic()

    def snapshot(self):
        with self.lock:
            now = time.monotonic()
            return {
                "frame_health_checked": False,
                "heartbeat_age_s": {
                    output: None if seen is None else round(now - seen, 1)
                    for output, seen in self.seen.items()
                },
                "automatic_restarts": len(self.restarts),
                "recovery_limited": self.limited,
            }

    def check(self, active, pid):
        with self.lock:
            now = time.monotonic()
            if not active or pid != self.pid:
                self.pid = pid if active else None
                self.started = now
                self.seen = dict.fromkeys(OUTPUTS)
                return None
            stale = [
                output for output, seen in self.seen.items()
                if (now - self.started >= STARTUP_SECONDS if seen is None
                    else now - seen >= STALE_SECONDS)
            ]
            while self.restarts and now - self.restarts[0] >= RESTART_WINDOW_SECONDS:
                self.restarts.popleft()
            if not stale:
                return None
            if len(self.restarts) >= MAX_RESTARTS:
                if not self.limited:
                    logging.error("Recovery limited: three browser restarts in 15 minutes")
                self.limited = True
                return None
            self.limited = False
            self.restarts.append(now)
            self.started = now
            self.seen = dict.fromkeys(OUTPUTS)
            return stale


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        prefix = "/_kiosk/heartbeat/"
        output = self.path.removeprefix(prefix)
        if not self.path.startswith(prefix) or output not in OUTPUTS:
            self.send_error(404)
            return
        origins = {
            f"http://localhost:{self.server.server_port}",
            f"http://127.0.0.1:{self.server.server_port}",
        }
        if self.headers.get("Origin") not in origins:
            self.send_error(403)
            return
        if self.headers.get("Content-Length", "0") != "0" or "Transfer-Encoding" in self.headers:
            self.send_error(400)
            return
        self.server.health.heartbeat(output)
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        if self.path != "/_kiosk/health":
            super().do_GET()
            return
        payload = json.dumps(self.server.health.snapshot()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_request(self, code="-", size="-"):
        if code != 204:
            super().log_request(code, size)


def monitor(health, stop):
    while not stop.wait(5):
        try:
            result = subprocess.run(
                ["systemctl", "--user", "show", "traincam-kiosk.service",
                 "--property=ActiveState", "--property=MainPID"],
                check=True, capture_output=True, text=True, timeout=5,
            )
            state = dict(line.split("=", 1) for line in result.stdout.splitlines())
            stale = health.check(state["ActiveState"] == "active", state["MainPID"])
            if stale:
                logging.error("Restarting kiosk: no page heartbeat from outputs %s", stale)
                subprocess.run(
                    ["systemctl", "--user", "restart", "traincam-kiosk.service"],
                    check=True, timeout=20,
                )
        except (OSError, subprocess.SubprocessError, KeyError, ValueError) as error:
            logging.error("Kiosk recovery command failed: %s", error)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--watchdog", action="store_true")
    args = parser.parse_args()
    if not args.directory.is_dir():
        parser.error("--directory must exist")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    handler = partial(Handler, directory=str(args.directory))
    with ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        server.health = Health()
        stop = threading.Event()
        if args.watchdog:
            threading.Thread(target=monitor, args=(server.health, stop), daemon=True).start()
        try:
            server.serve_forever()
        finally:
            stop.set()


if __name__ == "__main__":
    main()
