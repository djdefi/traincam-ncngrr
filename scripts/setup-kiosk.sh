#!/usr/bin/env bash
# Set up the Pi 5 display receiver as a self-healing kiosk. Run ON the Pi 5.
#
# WHY NOT JUST POINT CHROMIUM AT THE CAMERA (what docs/RECEIVER.md describes):
# because viewer.html is SERVED BY the camera Pi. Once the page is loaded it
# reconnects fine on its own (client/viewer.html backs off and retries), so a
# camera that disappears mid-show recovers without help. But if the camera is
# down at the moment Chromium loads the page, Chromium shows a network error
# page and NEVER retries - there is no reload logic on an error page.
#
# That used to be a corner case. It is now a certainty: the camera runs on
# battery (measured 5.32h) and the plan is to swap packs mid-show, so the camera
# WILL be absent for a minute at a time. Any kiosk reboot or Chromium restart
# during that window leaves a dead screen until a human intervenes.
#
# Fix: keep a local copy of the page and serve it from localhost. The page then
# always loads, and its existing WHEP reconnect handles the camera coming and
# going. viewer.html already supports pointing WHEP elsewhere via ?whepBase=
# (docs/NETWORK.md), so this needs no change to the viewer itself.
#
# Idempotent: safe to re-run. Undo with --uninstall.
set -euo pipefail

CAMERA="${CAMERA:-traincam1.local}"
WHEP_PORT="${WHEP_PORT:-8889}"
LOCAL_PORT="${LOCAL_PORT:-8081}"
WWW="$HOME/traincam-kiosk"
UNIT_DIR="$HOME/.config/systemd/user"
URL="http://localhost:${LOCAL_PORT}/viewer.html?whepBase=http://${CAMERA}:${WHEP_PORT}"

if [[ "${1:-}" == "--uninstall" ]]; then
  systemctl --user disable --now traincam-kiosk.service traincam-kiosk-www.service 2>/dev/null || true
  rm -f "$UNIT_DIR"/traincam-kiosk.service "$UNIT_DIR"/traincam-kiosk-www.service
  systemctl --user daemon-reload 2>/dev/null || true
  echo "uninstalled. Screen blanking NOT re-enabled; use raspi-config if you want it back."
  exit 0
fi

command -v chromium-browser >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1 || {
  echo "ERROR: no chromium found. apt install chromium-browser" >&2; exit 1; }
CHROMIUM="$(command -v chromium-browser || command -v chromium)"

mkdir -p "$WWW" "$UNIT_DIR"

# Fetch the page from the camera if we can, otherwise keep whatever is already
# there. Deliberately NOT fatal: the whole point is to work when the camera is
# absent, and a stale local copy still beats a Chromium error page.
if curl -fsS --max-time 10 "http://${CAMERA}:8080/viewer.html" -o "$WWW/viewer.html.new" 2>/dev/null; then
  mv "$WWW/viewer.html.new" "$WWW/viewer.html"
  echo "fetched viewer.html from ${CAMERA}"
elif [[ -f "$WWW/viewer.html" ]]; then
  rm -f "$WWW/viewer.html.new"
  echo "WARNING: camera unreachable, keeping existing local copy"
else
  rm -f "$WWW/viewer.html.new"
  echo "ERROR: camera unreachable and no local copy exists." >&2
  echo "       Bring the camera up once, or copy client/viewer.html to $WWW/" >&2
  exit 1
fi

# ponytail: python3 -m http.server, not the camera's viewer_server.py. That one
# also serves a status API the kiosk never calls. Static files are the whole job.
cat > "$UNIT_DIR/traincam-kiosk-www.service" <<EOF
[Unit]
Description=TrainCam kiosk local page server
[Service]
Type=simple
WorkingDirectory=$WWW
ExecStart=/usr/bin/python3 -m http.server $LOCAL_PORT --bind 127.0.0.1
Restart=always
RestartSec=2
[Install]
WantedBy=default.target
EOF

# --disable-session-crashed-bubble AND --disable-infobars matter after a power
# cut: without them Chromium comes back asking "Restore pages?" over the video
# and waits for a click that nobody will give it.
cat > "$UNIT_DIR/traincam-kiosk.service" <<EOF
[Unit]
Description=TrainCam kiosk browser
After=graphical-session.target traincam-kiosk-www.service
Wants=traincam-kiosk-www.service
[Service]
Type=simple
ExecStart=$CHROMIUM --kiosk --noerrdialogs --disable-infobars \\
  --disable-session-crashed-bubble --disable-features=Translate \\
  --no-first-run --autoplay-policy=no-user-gesture-required \\
  --check-for-update-interval=31536000 \\
  "$URL"
Restart=always
RestartSec=5
[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now traincam-kiosk-www.service traincam-kiosk.service

# Screen blanking. raspi-config's helper is used rather than `xset s off`
# (which docs/RECEIVER.md suggests) because Pi OS Bookworm defaults to Wayland,
# where xset is a silent no-op - it "works" and the screen still blanks.
#
# sudo -n (non-interactive) on purpose: this is the ONLY step in the whole
# script that needs root, and a plain `sudo` here would sit forever waiting for
# a password nobody is going to type at a kiosk. Everything above is $HOME and
# `systemctl --user`, so the kiosk fully works without root - it would just
# blank the screen eventually. Failing loudly and continuing beats hanging.
if ! command -v raspi-config >/dev/null 2>&1; then
  echo "WARNING: no raspi-config; disable screen blanking yourself" >&2
elif sudo -n raspi-config nonint do_blanking 1 2>/dev/null; then
  echo "screen blanking disabled"
else
  echo >&2
  echo "WARNING: could not disable screen blanking (needs a sudo password)." >&2
  echo "         The kiosk still works - the screen will just blank when idle." >&2
  echo "         Run this yourself when you have the password:" >&2
  echo "           sudo raspi-config nonint do_blanking 1" >&2
fi

echo
echo "kiosk URL: $URL"
echo "status:    systemctl --user status traincam-kiosk"
echo "logs:      journalctl --user -u traincam-kiosk -f"
