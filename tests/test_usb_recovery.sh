#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch

source = Path("ansible/roles/trainview/templates/usb-relay.py.j2").read_text()
source = source.replace("{{ trainview_usb_camera }}", "/dev/video0").replace("{{ trainview_usb_relay_port }}", "8083")
relay = {"__name__": "test"}
exec(compile(source, "usb-relay", "exec"), relay)

def child(code):
    return subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, bufsize=0)

# A writer can stay alive indefinitely without producing a frame.
p = child("import time; time.sleep(30)")
started = time.monotonic()
try:
    try:
        relay["capture"](p)
        raise AssertionError("silent capture did not time out")
    except TimeoutError:
        assert 4.5 <= time.monotonic() - started < 7
finally:
    relay["stop_capture"](p)
    p.stdout.close()

# A partial JPEG arriving every 100ms must not reset the complete-frame deadline.
p = child("import os,time; os.write(1,b'\\xff\\xd8');\nwhile True: os.write(1,b'x'); time.sleep(.1)")
try:
    try:
        relay["capture"](p)
        raise AssertionError("partial-frame capture did not time out")
    except TimeoutError:
        pass
finally:
    relay["stop_capture"](p)
    p.stdout.close()

# A child ignoring SIGTERM must not wedge the ingest loop during Popen.__exit__.
p = child("import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); os.write(1,b'ready'); time.sleep(30)")
assert relay["read_chunk"](p.stdout) == b"ready"
started = time.monotonic()
relay["stop_capture"](p)
assert p.returncode is not None and time.monotonic() - started < 4
p.stdout.close()

# Complete small frames must be delivered without waiting for a 64KiB read.
p = child("import os,time; os.write(1,b'\\xff\\xd8jpeg\\xff\\xd9'); time.sleep(.1)")
try:
    try:
        relay["capture"](p)
    except EOFError:
        pass
    assert relay["sequence"] == 1 and relay["latest"] == b"\xff\xd8jpeg\xff\xd9"
finally:
    relay["stop_capture"](p)
    p.stdout.close()
print("PASS: silent capture, incomplete frames, SIGTERM resistance and small JPEG delivery")
PY
