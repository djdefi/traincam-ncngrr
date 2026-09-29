#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

grep -q '^  hosts: trainview$' kiosk.yml
grep -q '^\[trainview\]$' inventory
grep -q 'ansible/roles/traincam/templates/viewer.html.j2' ansible/roles/trainview/tasks/main.yml
if grep -q 'curl.*viewer.html' ansible/roles/trainview/tasks/main.yml; then
  echo "kiosk role must deploy the repository viewer, not fetch mutable camera state" >&2
  exit 1
fi
grep -q 'lightdm.service' ansible/roles/trainview/tasks/main.yml
grep -q 'archive.raspberrypi.com/debian/' ansible/roles/trainview/tasks/main.yml
grep -q 'linux-image-arm64' ansible/roles/trainview/tasks/main.yml
grep -q 'NetworkManager-wait-online.service' ansible/roles/trainview/tasks/main.yml
grep -q '.config/labwc/autostart' ansible/roles/trainview/tasks/main.yml
grep -q 'autologin-session=labwc' ansible/roles/trainview/tasks/main.yml
grep -q 'Override Raspberry Pi OS desktop session defaults' ansible/roles/trainview/tasks/main.yml
grep -q -- '--user-data-dir=%t/traincam-chromium-profile-1' ansible/roles/trainview/templates/traincam-kiosk.service.j2
grep -q 'ExecStartPre=/bin/rm -rf %t/traincam-chromium-profile-1 %t/traincam-chromium-profile-2' ansible/roles/trainview/templates/traincam-kiosk.service.j2
python3 - <<'PY'
import io
import subprocess
from pathlib import Path

unit = Path("ansible/roles/trainview/templates/traincam-kiosk.service.j2").read_text()
first, second = unit.split("--class=TrainCam-HDMI-2")
assert "output=usb" in first, "the larger HDMI-1 display must show USB"
assert "output=1" in second, "the smaller HDMI-2 display must show train/visitor content"

path = Path("ansible/roles/trainview/templates/esp32-relay.py.j2")
source = path.read_text().replace("{{ trainview_esp32_camera }}", "camera").replace(
    "{{ trainview_esp32_relay_port }}", "8082"
)
relay = {"__name__": "test"}
exec(compile(source, path, "exec"), relay)
jpeg = b"\xff\xd8test\xff\xd9"
stream = io.BytesIO(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: 8\r\n\r\n" + jpeg)
assert relay["read_frame"](stream) == jpeg
assert 'path = self.path.partition("?")[0]' in source
assert 'if path == "/status":' in source
assert 'if path != "/stream":' in source
assert 'status["frame_sequence"] = sequence' in source

usb_path = Path("ansible/roles/trainview/templates/usb-relay.py.j2")
usb_source = usb_path.read_text().replace("{{ trainview_usb_camera }}", "/dev/video0").replace(
    "{{ trainview_usb_relay_port }}", "8083"
)
usb_relay = {"__name__": "test"}
exec(compile(usb_source, usb_path, "exec"), usb_relay)
frame, remainder = usb_relay["extract_frame"](b"junk\xff\xd8jpeg\xff\xd9next")
assert frame == b"\xff\xd8jpeg\xff\xd9"
assert remainder == b"next"
assert 'Access-Control-Allow-Origin' in usb_source
process = subprocess.Popen(["sleep", "1"], stdout=subprocess.PIPE)
assert usb_relay["read_chunk"](process.stdout, 0.01) is None
process.terminate()
process.wait()
PY
grep -q 'kiosk-server.py.*--watchdog' ansible/roles/trainview/templates/traincam-kiosk-www.service.j2
grep -q 'visitor/' ansible/roles/trainview/tasks/main.yml

echo "✓ kiosk OS configuration, watchdog and visitor assets are owned by Ansible"
