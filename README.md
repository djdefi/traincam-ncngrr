# TrainCam

**See what the engineer sees** — a live camera feed from a model train, powered by the track.

## What Is It?

A tiny camera rides on a model train and streams the engineer's view to any screen.

```
🚂 Camera on Train  ───►  📡 WiFi  ───►  📺 Phone / TV / Laptop
```

**No batteries to swap** — the camera harvests power from the DCC track.

## Hardware Options

| Option | Size | Best For |
|--------|------|----------|
| **Raspberry Pi Zero W** | Credit card | Higher quality, more features |
| **ESP32-S3 XIAO** | Postage stamp | Tighter spaces, simpler setup |

See [docs/HARDWARE.md](docs/HARDWARE.md) for the full power chain (rectifier → buck converter → battery → camera).

## Quick Start

### Pi Zero (Ansible deployment)

```bash
# 1. Clone the repo
git clone https://github.com/djdefi/traincam-ncngrr
cd traincam-ncngrr

# 2. Edit inventory with your Pi's hostname
vim inventory

# 3. Deploy
ansible-playbook -i inventory traincam.yml

# 4. View the stream
open http://traincam1.local:8080/viewer.html
```

### ESP32 (Arduino)

1. Open `CameraWebServer/CameraWebServer.ino` in Arduino IDE
2. Set your WiFi credentials (lines 12-13)
3. Upload to XIAO ESP32S3 Sense
4. Open `http://<esp32-ip>/` in browser

## Project Structure

```
traincam-ncngrr/
├── ansible/              # Ansible role for Pi deployment
├── CameraWebServer/      # ESP32 Arduino firmware
├── client/               # WebRTC viewer (HTML/JS)
├── docs/                 # Documentation
│   ├── ARCHITECTURE.md   # System design (all skill levels)
│   ├── HARDWARE.md       # Power chain details
│   ├── NETWORK.md        # WiFi, ports, mDNS
│   └── PRINTABLE_HANDOUT.md  # One-page handout for demos
├── tests/                # Automated tests
└── traincam.yml          # Main Ansible playbook
```

## Streaming Stack (Pi)

```
rpicam-vid (H.264) → ffmpeg → MediaMTX → WebRTC/RTSP
                                  ↓
                           viewer.html
```

| Port | Protocol | What |
|------|----------|------|
| 8080 | HTTP | Web viewer |
| 8554 | RTSP | Direct stream (VLC) |
| 8889 | WebRTC | Low-latency browser view |

## Configuration

Edit `group_vars/traincam.yml` for resolution, FPS, and latency:

```yaml
traincam_width: 1280
traincam_height: 720
traincam_fps: 24
LATENCY_MODE: ultra_plus  # Options: low (~1s), ultra (~0.5s), ultra_plus (~0.25s)
```

## Development

```bash
# Lint everything
./scripts/lint.sh

# Run tests
./tests/run_tests.sh
```

## Roadmap

- [ ] Multiple cameras (cab, yard, rear view)
- [ ] ESP32 mDNS discovery ([issue](issues/1.md))
- [ ] Recording & playback
- [ ] Audio from train

## Contributing

Built by hobbyists, for hobbyists. All skill levels welcome:
- **Train folks:** Test on your layout, share feedback
- **Electronics:** Improve power supply, try new hardware
- **Software:** Add features, fix bugs, improve docs

## License

Open source. See [LICENSE](LICENSE) for details.

---

**Contact:** djdefi@gmail.com • [Open an issue](https://github.com/djdefi/traincam-ncngrr/issues)
