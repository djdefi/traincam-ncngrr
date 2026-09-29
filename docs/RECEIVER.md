# TrainCam display receiver

The Raspberry Pi 5 receiver runs two independent 1920x1080 HDMI displays:

- **HDMI-A-1:** live Pi camera, then ESP32 if it has fresh frames; otherwise
  local photographs and visitor information.
- **HDMI-A-2:** full-screen USB camera; visitor information while USB is absent
  or recovering. The USB display does not depend on the Pi camera or WiFi.

Visitor slides rotate every 20 seconds and contain locally stored photos and
QR codes for the website, historic map, volunteering, and donation inquiries.
The kiosk needs no internet to show them. Scanning a QR code opens the public
website on the visitor's phone, which does require internet.

## Provisioning

Start with 64-bit Raspberry Pi OS Desktop, the `train` user, SSH, and a working
desktop session. From this repository:

```bash
ansible-playbook -i inventory kiosk.yml
```

`scripts/setup-kiosk.sh` is a compatibility wrapper for this command. The
playbook installs runtime packages, deploys the viewer, relays, offline assets,
watchdog, and display layout, then restarts the kiosk services. **Provisioning
interrupts the displays.** Do not run a full playbook during a public show just
to recover a camera. The old standalone installer and its `--uninstall` option
are no longer supported.

Configuration lives in `group_vars/trainview.yml`. The layout's USB camera is
selected by `/dev/v4l/by-id/usb-Razer_Inc_Razer_Kiyo_Pro-video-index0`, not by a
potentially changing `/dev/video0` number. Update that value for another camera.
The role defaults to `/dev/video0` for generic receivers.

## Recovery behavior

The USB relay requires a **complete JPEG within five seconds**, including at
startup. No bytes, partial frames, oversized frames, and EOF all cause capture
to reopen after two seconds. A stuck FFmpeg receives SIGTERM, then SIGKILL
after two seconds. HTTP streams close when frames go stale, rather than
holding a frozen image indefinitely. `/status` returns 503 without fresh
frames. Slow/disconnected HTTP clients have bounded waits.

The browser selector uses viewer-reported video health, not HTTP reachability:
WebRTC requires an advancing playback clock; MJPEG requires an image load
plus fresh relay frame status. Loss selects visitor information; ten seconds
of sustained good video is required before switching back. WHEP connection
attempts and status requests are time-bounded. Unresponsive child pages
reload at most once per minute.

The local server watches a separate heartbeat from the currently visible
page on each display. A missing initial page gets 180 seconds; a lost heartbeat
gets 45 seconds. It restarts only the browser service, with at most three
attempts in a rolling 15-minute window. An intentionally stopped browser stays
stopped. This is **not proof that the GPU or physical monitor is displaying
frames**: JavaScript can remain responsive during a graphics fault.

## Live checks

```bash
ssh train@trainview1.local
curl -fsS http://127.0.0.1:8081/_kiosk/health
curl -sS http://127.0.0.1:8083/status
sudo journalctl -b -u user@1000.service --no-pager
sudo journalctl -b _SYSTEMD_USER_UNIT=traincam-usb-relay.service --no-pager
sudo journalctl -b _SYSTEMD_USER_UNIT=traincam-kiosk-www.service --no-pager
```

Increasing `frame_sequence` and a small `frame_age_ms` indicate fresh capture.
`frame_sequence: 0` or `frame_age_ms: null` means capture has not succeeded;
an active systemd unit alone does not establish video health.

On September 29, 2026, the deployed old relay was stuck in a blocking read,
FFmpeg consumed a core, and the kernel reported USB/UVC resets and errors.
The bounded capture fix allowed retries; unplugging and reconnecting the
camera restored frames without another service restart. That does **not**
establish whether the original USB fault was cable, camera firmware, host
controller, or power. Use a short known-good cable directly into the Pi and
investigate recurring kernel USB errors; software cannot guarantee recovery
from a device that requires physical power cycling.

In the live recovery exercise, a deliberately stopped FFmpeg was replaced and
fresh USB frames resumed within 15 seconds. With the Pi video service stopped
but its HTTP status still answering, the first display showed visitor slides
while USB continued on the second; restoring video restored the first display.
These targeted checks are not a substitute for the cold-boot and soak checks.
USB3 U1/U2 controls reported `disabled` during inspection, so the kernel's
failed U1-enable messages alone are not proof that active link power saving
caused the fault. No kernel USB quirk was applied.

## Before the Christmas fair

```bash
bash tests/test_usb_recovery.sh
bash tests/test_kiosk_watchdog.sh
bash tests/test_kiosk_provisioning.sh
bash tests/test_viewer_reconnect.sh
CHROME=/path/to/chromium node tests/test_kiosk_browser.mjs
```

On hardware, verify both HDMI outputs separately, unplug/replug USB, start
without network cameras, return the train camera, and run an extended soak.
Repeat cold boots and power-loss checks on a spare card before calling the
system fair-ready. The existing live root filesystem is writable and the
clock is unsynchronized; this change does not enable overlay root, change the
network, upgrade graphics drivers, or reboot the Pi.

Offline photos were approved for this layout kiosk by its operator. Sources:
[gallery](https://ncngmodelrailroad.org/gallery/),
[volunteering](https://ncngmodelrailroad.org/volunteer/),
[support](https://ncngmodelrailroad.org/donate/), and
[historic map](https://ncngmodelrailroad.org/map/), accessed September 29, 2026.
No online donation checkout or confirmed sponsorship program is implied.
The QR PNGs are generated locally with Python `qrcode` 8.2, error correction M,
ten-pixel modules and a four-module quiet zone. No runtime QR dependency or
third-party QR service is used.
