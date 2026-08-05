# TrainCam Display Receiver

The display receiver is a Raspberry Pi 5 connected to monitor(s) that shows the live train camera feed. It auto-starts the stream viewer on boot.

## Hardware

- Raspberry Pi 5
- Monitor connected via HDMI
- Network connection (WiFi or Ethernet to `traincameranet`)

## Current Setup

The display receiver is configured to:
1. Boot into desktop
2. Auto-start Chromium in kiosk mode
3. Load the WebRTC viewer page (`viewer.html`)
4. Display the live stream from `traincam1`

## Auto-Start Configuration

### Recommended: `scripts/setup-kiosk.sh`

Run it on the Pi 5:

```bash
./scripts/setup-kiosk.sh              # CAMERA=traincam1.local by default
./scripts/setup-kiosk.sh --uninstall  # undo
```

It keeps a **local copy of `viewer.html` and serves it from localhost**, then
points Chromium at that with `?whepBase=` aimed at the camera.

That indirection is the point. `viewer.html` is normally served *by the camera*,
so if the camera is down when Chromium loads the page, Chromium shows a network
error page and never retries — there is no reload logic on an error page. Once
the page *is* loaded it reconnects on its own, so a camera that vanishes
mid-show recovers unaided. Serving locally means the page always loads and the
existing WHEP reconnect covers the rest.

This matters because the camera runs on battery (measured 5.32 h) and packs get
swapped mid-show, so the camera is *expected* to be absent for a minute at a
time. Any kiosk reboot or Chromium restart in that window would otherwise leave
a dead screen until someone notices.

The script also sets `Restart=always`, suppresses the "Restore pages?" bubble
that would otherwise sit over the video after a power cut, and disables screen
blanking via `raspi-config` rather than `xset` — see the warning below.

The two manual options below still work and are kept for reference.

### Option A: Autostart Desktop Entry

Create `~/.config/autostart/traincam-viewer.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=TrainCam Viewer
Exec=chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble http://traincam1.local:8080/viewer.html
X-GNOME-Autostart-enabled=true
```

### Option B: Systemd User Service

Create `~/.config/systemd/user/traincam-viewer.service`:

```ini
[Unit]
Description=TrainCam WebRTC Viewer
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/chromium-browser --kiosk --noerrdialogs --disable-infobars http://traincam1.local:8080/viewer.html
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

Enable with:
```bash
systemctl --user enable traincam-viewer.service
systemctl --user start traincam-viewer.service
```

## Viewer URL Options

| URL | Description |
|-----|-------------|
| `http://traincam1.local:8080/viewer.html` | Default, uses mDNS hostname |
| `http://192.168.x.x:8080/viewer.html` | Direct IP if mDNS not working |
| `?whepPort=8889` | Explicit WHEP port (default) |
| `?whepBase=http://relay:8889` | Override WHEP server entirely |

## Fallback: VLC for RTSP

If WebRTC has issues, use VLC to play the RTSP stream directly:

```bash
vlc rtsp://traincam1.local:8554/traincam
```

Or auto-start VLC instead:

```ini
[Desktop Entry]
Type=Application
Name=TrainCam VLC
Exec=vlc --fullscreen --no-video-title-show rtsp://traincam1.local:8554/traincam
X-GNOME-Autostart-enabled=true
```

## Multiple Cameras

To add more cameras, create additional viewer pages or use tabs:

```bash
# Example: cycle between cameras
chromium-browser --kiosk http://traincam1.local:8080/viewer.html http://traincam2.local:8080/viewer.html
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Black screen | Check network connectivity to camera Pi |
| "Cannot reach server" | Verify MediaMTX is running on camera/relay |
| Audio issues | Viewer is muted by default (video only) |
| High latency | Check `LATENCY_MODE` setting, try `ultra_plus` |
| mDNS not resolving | Use IP address instead of `.local` hostname |

## Display Settings

For best results:
- Set Pi display resolution to match your monitor
- Disable screen blanking: `sudo raspi-config nonint do_blanking 1`
- Hide mouse cursor: `unclutter -idle 1` (install with `apt install unclutter`)

> **Do not use `xset s off && xset -dpms` on Bookworm.** Pi OS Bookworm defaults
> to Wayland, where `xset` is a silent no-op — it appears to succeed and the
> screen still blanks partway through the show. Use the `raspi-config` command
> above, which handles both X11 and Wayland.
