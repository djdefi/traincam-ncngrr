#!/usr/bin/env python3
"""Serve the TrainCam viewer and the small status API used by RailCam."""

import http.server
import json
import socket
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

PORT = 8080
RTSP_PORT = 8554
WEBRTC_PORT = 8889
WWW_DIR = Path.home() / "www"
START_TIME = time.monotonic()


def _read_number(path, transform):
    try:
        return transform(Path(path).read_text(encoding="ascii").split()[0])
    except (OSError, ValueError, IndexError):
        return 0


def _free_memory():
    try:
        for line in Path("/proc/meminfo").read_text(encoding="ascii").splitlines():
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) * 1024
    except (OSError, ValueError, IndexError):
        pass
    return 0


def _local_ip():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 9))
        return sock.getsockname()[0]
    except OSError:
        return "unknown"
    finally:
        sock.close()


def get_status():
    temperature = _read_number(
        "/sys/class/thermal/thermal_zone0/temp", lambda value: int(value) / 1000
    )
    return {
        "hostname": socket.gethostname(),
        "uptime_s": int(_read_number("/proc/uptime", float)),
        "service_uptime_s": int(time.monotonic() - START_TIME),
        "temperature_c": round(temperature, 1),
        "temperature_f": round(temperature * 9 / 5 + 32, 1),
        "free_mem": _free_memory(),
        "ip": _local_ip(),
        "type": "pi",
        "stream": "webrtc",
        "viewer_port": PORT,
        "rtsp_port": RTSP_PORT,
        "webrtc_port": WEBRTC_PORT,
    }


class ViewerHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WWW_DIR, **kwargs)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/status":
            payload = json.dumps(get_status()).encode()
            self.send_response(http.HTTPStatus.OK)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(payload)
            return
        if path == "/player":
            self.send_response(http.HTTPStatus.FOUND)
            self.send_header("Location", "/viewer.html")
            self.end_headers()
            return
        super().do_GET()


def main():
    global PORT, RTSP_PORT, WEBRTC_PORT
    PORT = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    RTSP_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else RTSP_PORT
    WEBRTC_PORT = int(sys.argv[3]) if len(sys.argv) > 3 else WEBRTC_PORT
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), ViewerHandler).serve_forever()


if __name__ == "__main__":
    main()
