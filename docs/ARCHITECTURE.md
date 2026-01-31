# TrainCam Architecture

**TrainCam** is an open-source camera system for model railroads. It lets you see what the engineer would see — a live video feed from a tiny camera riding on a moving train, displayed on a monitor for everyone to enjoy.

This project is built specifically for historic model railroad clubs and layouts, designed to be expandable, maintainable, and accessible to hobbyists of all skill levels.

---

## The Simple Version
*What a 10-year-old can understand*

Imagine you're a tiny person riding in the locomotive. What would you see? TrainCam shows you exactly that!

**How it works:**
1. 📷 A tiny camera rides on the train
2. 📡 The camera sends video through the air (like WiFi on your tablet)
3. 📺 The video shows up on a TV screen

```
    🚂 Train with Camera
          │
          │ (WiFi signal through the air)
          ▼
    📺 TV Screen shows what the train sees!
```

**The cool part:** The camera gets its power from the same tracks the train runs on! No batteries to change.

---

## The Learning Version  
*What a student would understand*

TrainCam is a three-part system that captures, transmits, and displays live video from a moving model train.

### The Three Parts

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   PART 1              PART 2                   PART 3                  │
│   ┌──────────┐        ┌──────────────┐         ┌──────────────┐        │
│   │ CAMERA   │  WiFi  │   SERVER     │  Cable  │   DISPLAY    │        │
│   │ on train │ ─────► │   computer   │ ──────► │   screen     │        │
│   └──────────┘        └──────────────┘         └──────────────┘        │
│                                                                         │
│   Captures video      Receives &               Shows the               │
│   and sends it        processes video          live feed               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Part 1: The Onboard Camera

A small computer with a camera, small enough to fit in a freight car or behind a locomotive. Two options:

| Option | Size | Best For |
|--------|------|----------|
| Raspberry Pi Zero W | Credit card size | Higher quality video, more features |
| ESP32-S3 | Postage stamp size | Smaller spaces, simpler setup |

**Power:** The camera harvests electricity from the track rails (the same power that runs the train), converts it to the right voltage, and stores some in a small battery for backup.

### Part 2: The Streaming Server

A Raspberry Pi (small computer) sitting trackside that:
- Receives the video signal over WiFi
- Converts it to a format browsers can display
- Serves it to anyone who wants to watch

**Why not stream directly?** The onboard camera is tiny and battery-limited. Offloading the heavy work to a trackside computer means better video and longer runtime.

### Part 3: The Display

Another Raspberry Pi connected to a TV or monitor. It automatically opens a web browser and shows the live train camera feed. Turn it on, and it just works.

### The Network

All the parts talk to each other over a private WiFi network called `traincameranet`. This keeps the video fast and reliable, separate from regular internet traffic.

---

## The Practical Version
*What a hands-on builder needs to know*

### Hardware Requirements

| Component | Recommended | Notes |
|-----------|-------------|-------|
| Onboard camera | Raspberry Pi Zero W + Camera Module v2 | Or ESP32-S3 for tighter spaces |
| Streaming server | Raspberry Pi 4 or 5 | Can be same device as display |
| Display | Raspberry Pi 5 + HDMI monitor | Auto-starts on boot |
| Power supply | See [HARDWARE.md](HARDWARE.md) | DCC → rectifier → buck → battery → camera |
| WiFi | Any router you control | Set your own SSID/password |

### Software Stack

```
ONBOARD CAMERA (Pi Zero)          STREAMING SERVER           DISPLAY
┌─────────────────────┐          ┌──────────────────┐      ┌─────────────────┐
│ rpicam-vid          │          │ MediaMTX         │      │ Chromium        │
│ (captures H.264)    │──WiFi───►│ (RTSP + WebRTC)  │─────►│ (kiosk mode)    │
│         │           │          │                  │      │                 │
│         ▼           │          │ Python HTTP      │      │ viewer.html     │
│ ffmpeg              │          │ (serves viewer)  │      │                 │
│ (sends to server)   │          │                  │      │                 │
└─────────────────────┘          └──────────────────┘      └─────────────────┘
```

### Quick Start

```bash
# 1. Set up your Pi Zero with Raspberry Pi OS
# 2. Connect it to traincameranet WiFi
# 3. From your laptop, deploy the software:

git clone https://github.com/djdefi/traincam-ncngrr
cd traincam-ncngrr
ansible-playbook -i inventory traincam.yml

# 4. View the stream at:
#    http://traincam1.local:8080/viewer.html
```

### Network Ports

| Port | What It Does |
|------|--------------|
| 8554 | RTSP video stream (for VLC, etc.) |
| 8889 | WebRTC video (for web browsers) |
| 8080 | Web page viewer |

### Latency Tuning

How quickly the display responds to what the train sees:

| Mode | Delay | Use Case |
|------|-------|----------|
| `ultra_plus` | ~0.25 sec | Best responsiveness, uses more bandwidth |
| `ultra` | ~0.5 sec | Good balance |
| `low` | ~1 sec | Stable, less bandwidth |

Set in `group_vars/traincam.yml` with `LATENCY_MODE`.

---

## The Contributor Version
*What developers and maintainers need to build the future*

### Repository Structure

```
traincam-ncngrr/
├── ansible/roles/traincam/     # Ansible role for Pi deployment
│   ├── tasks/main.yml          # Installation steps
│   ├── templates/              # Config file templates
│   │   ├── publish.sh.j2       # Main capture script
│   │   ├── stream.conf.j2      # Runtime configuration
│   │   └── mediamtx.yml.j2     # MediaMTX config
│   └── handlers/               # Systemd restart handlers
├── CameraWebServer/            # ESP32 Arduino firmware
├── client/                     # WebRTC viewer HTML/JS
├── docs/                       # Documentation (you are here)
├── tests/                      # Bash test suite
├── scripts/                    # Development utilities
├── group_vars/                 # Ansible variables
└── inventory                   # Target hosts
```

### Key Design Decisions

1. **Ansible for deployment** — Reproducible, documented infrastructure. Run the playbook, get a working camera.

2. **MediaMTX as the relay** — Single binary, supports RTSP input and WebRTC output, low latency, no transcoding needed.

3. **rpicam-vid + ffmpeg pipeline** — Pi's native camera tool pipes H.264 directly to ffmpeg, which sends it to MediaMTX via RTSP. No re-encoding.

4. **Battery-backed power** — USB battery bank buffers the DCC track power, keeping the Pi running through dirty track and switch gaps.

5. **mDNS for discovery** — Devices find each other by name (`traincam1.local`) rather than IP addresses.

### Testing

```bash
# Run all tests (38 tests covering latency modes, config parsing, network config)
./tests/run_tests.sh

# Lint Ansible and shell scripts
./scripts/lint.sh
```

### Extending the Platform

**Add a new camera:**
1. Add host to `inventory`
2. Set variables in `group_vars/`
3. Run playbook

**Add new latency mode:**
1. Edit `publish.sh.j2` KEYFRAME_INTERVAL logic
2. Add tests in `tests/test_latency_modes.sh`
3. Document in this file

**ESP32 improvements:**
1. mDNS discovery (see `issues/1.md`)
2. OTA firmware updates
3. Configuration via web interface

### Future Roadmap

- [ ] Multiple camera switching (cab cam, consist view, yard cam)
- [ ] Audio from train (optional microphone)
- [ ] Recording and playback
- [ ] Mobile app viewer
- [ ] Integration with layout control systems
- [ ] Locomotive detection (which train is which camera)

### Contributing

This is an open-source project for the model railroad community. Contributions welcome:

- **Train hobbyists:** Test on your layout, report what works and what doesn't
- **Electronics folks:** Improve the power supply design, try different hardware
- **Software developers:** Add features, fix bugs, improve documentation
- **Everyone:** Share photos, videos, and stories of TrainCam in action

---

## Links

| Document | Description |
|----------|-------------|
| [HARDWARE.md](HARDWARE.md) | Power supply chain from track to camera |
| [NETWORK.md](NETWORK.md) | WiFi, ports, and mDNS configuration |
| [RECEIVER.md](RECEIVER.md) | Display receiver setup |
| [DEMO_QUICK_REF.md](DEMO_QUICK_REF.md) | Quick reference for demos |
| [ONE_PAGER.md](ONE_PAGER.md) | 2-minute elevator pitch |
| [README.md](../README.md) | Project overview and quick start |

---

## Quick Access

**Viewer URL (works on any network):**
```
http://traincam1.local:8080/viewer.html
```
