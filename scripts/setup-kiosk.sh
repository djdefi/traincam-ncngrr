#!/usr/bin/env bash
# Set up the Pi 5 display receiver as a self-healing kiosk. Run ON the Pi 5.
#
# WHY NOT JUST POINT CHROMIUM AT THE CAMERA (what docs/RECEIVER.md describes):
# because viewer.html is SERVED BY the camera Pi. Once the page is loaded it
# reconnects fine on its own (the viewer backs off and retries), so a
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
AUTOSTART_DIR="$HOME/.config/autostart"
URL="http://localhost:${LOCAL_PORT}/viewer.html?whepBase=http://${CAMERA}:${WHEP_PORT}"

if [[ "${1:-}" == "--uninstall" ]]; then
  systemctl --user disable --now traincam-kiosk.service traincam-kiosk-www.service 2>/dev/null || true
  rm -f "$UNIT_DIR"/traincam-kiosk.service "$UNIT_DIR"/traincam-kiosk-www.service
  rm -f "$AUTOSTART_DIR"/traincam-kiosk.desktop
  systemctl --user daemon-reload 2>/dev/null || true
  echo "uninstalled. Screen blanking NOT re-enabled; use raspi-config if you want it back."
  exit 0
fi

command -v chromium-browser >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1 || {
  echo "ERROR: no chromium found. apt install chromium-browser" >&2; exit 1; }
CHROMIUM="$(command -v chromium-browser || command -v chromium)"

mkdir -p "$WWW" "$UNIT_DIR" "$AUTOSTART_DIR"

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
  echo "       Bring the camera up once so a copy can be cached." >&2
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
After=graphical-session.target traincam-kiosk-www.service xdg-desktop-portal.service
Wants=traincam-kiosk-www.service xdg-desktop-portal.service
[Service]
Type=simple
# default.target can start before LightDM has created the compositor socket.
# Chromium stays alive but never opens the page, so Restart=always cannot help.
# ponytail: Bookworm/Labwc uses wayland-0; wait for the real readiness signal.
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_RUNTIME_DIR=%t
ExecStartPre=/usr/bin/timeout 90 /bin/sh -c 'until /usr/bin/wlr-randr >/dev/null 2>&1; do sleep 1; done'
ExecStart=$CHROMIUM --kiosk --noerrdialogs --disable-infobars \\
  --disable-session-crashed-bubble --disable-features=Translate \\
  --user-data-dir=$WWW/chromium-profile \\
  --no-first-run --autoplay-policy=no-user-gesture-required \\
  --check-for-update-interval=31536000 \\
  "$URL"
Restart=always
RestartSec=5
EOF

# Starting the browser from default.target races LightDM: Chromium remains alive
# but never opens the page. XDG autostart runs inside the graphical session,
# after Labwc has created the display and D-Bus environment. It starts the
# systemd service so Restart=always still handles later browser crashes.
cat > "$AUTOSTART_DIR/traincam-kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=TrainCam kiosk
Exec=systemctl --user restart traincam-kiosk.service
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

systemctl --user daemon-reload
systemctl --user enable traincam-kiosk-www.service
systemctl --user disable traincam-kiosk.service 2>/dev/null || true
# `enable --now` leaves an already-running service on its old unit contents.
# Restart so re-running this idempotent installer actually applies its changes.
systemctl --user restart traincam-kiosk-www.service traincam-kiosk.service

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

# Two-panel kiosk: BOTH HDMI outputs must show the stream. kanshi (shipped on
# Pi OS Bookworm) mirrors them by putting both outputs at the same 0,0 origin in
# one logical space - labwc then scans that same region out to both connectors.
# This is the native compositor mirror; no extra service, no second browser.
# The second profile keeps a single panel working when only one monitor is
# connected. Output names are this appliance's two HDMI ports (wlr-randr).
KANSHI_CFG="$HOME/.config/kanshi/config"
mkdir -p "$(dirname "$KANSHI_CFG")"
KANSHI_WANT="$(cat <<'EOF'
profile {
	output HDMI-A-1 enable mode 1920x1080@60.000 position 0,0 transform normal
	output HDMI-A-2 enable mode 1920x1080@60.000 position 0,0 transform normal
}

profile {
	output HDMI-A-1 enable mode 1920x1080@60.000 position 0,0 transform normal
}
EOF
)"
if [[ -f "$KANSHI_CFG" && ! -f "$KANSHI_CFG.before-traincam-mirror" ]]; then
  cp "$KANSHI_CFG" "$KANSHI_CFG.before-traincam-mirror"
fi
if [[ "$(cat "$KANSHI_CFG" 2>/dev/null || true)" != "$KANSHI_WANT" ]]; then
  printf '%s\n' "$KANSHI_WANT" > "$KANSHI_CFG"
  echo "wrote kanshi mirror config ($KANSHI_CFG)"
fi
# kanshi reloads its config on SIGHUP; apply now without a reboot. kill -HUP on
# the specific pid (no name-based killers).
KPID="$(pgrep -x kanshi 2>/dev/null | head -1 || true)"
[[ -n "$KPID" ]] && kill -HUP "$KPID" 2>/dev/null || true

# Boot-time trimming (needs root). Best-effort, exactly like the blanking step:
# the kiosk works without it, it just boots slower. See scripts/optimize-boot.sh
# for the per-unit justification and --uninstall.
OPT="$(dirname "$0")/optimize-boot.sh"
if [[ -x "$OPT" ]]; then
  "$OPT" || echo "WARNING: boot optimizer did not complete (needs sudo?)" >&2
fi

echo
echo "kiosk URL: $URL"
echo "status:    systemctl --user status traincam-kiosk"
echo "logs:      journalctl --user -u traincam-kiosk -f"
