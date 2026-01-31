# Copilot Instructions for TrainCam

This repository packages a Raspberry Pi camera streaming pipeline with Ansible provisioning, plus ESP32 camera firmware.

**Key Docs:** See `docs/ARCHITECTURE.md` for system overview, `docs/DEMO_QUICK_REF.md` for meetup demo.

**Viewer URL:** `http://traincam1.local:8080/viewer.html`

## Architecture

**Streaming Pipeline (Pi):**
- `rpicam-vid` captures H.264 → pipes to MediaMTX RTSP ingest
- MediaMTX exposes WebRTC (WHEP) on port 8889 and RTSP on port 8554
- Static HTML/JS viewer served via Python http.server on port 8080

**Provisioning:**
- Single Ansible role at `ansible/roles/traincam/` deploys everything
- Entry point: `ansible-playbook -i inventory traincam.yml`
- All runtime config is templated to `/etc/traincam/stream.conf` on the Pi

**ESP32 Camera:**
- Arduino sketch in `CameraWebServer/` for Seeed Studio XIAO ESP32S3
- See `issues/1.md` for planned mDNS feature

## Commands

```bash
# Deploy to Pi (requires SSH access)
ansible-playbook -i inventory traincam.yml

# Run all tests
./tests/run_tests.sh

# Run linting
./scripts/lint.sh

# Or lint individually
ansible-lint
shellcheck --shell=bash ansible/roles/traincam/templates/*.sh.j2
```

## Key Files

| Purpose | Location |
|---------|----------|
| Main playbook | `traincam.yml` |
| Role variables | `group_vars/traincam.yml` |
| Stream capture script template | `ansible/roles/traincam/templates/stream.sh.j2` |
| MediaMTX config template | `ansible/roles/traincam/templates/mediamtx.yml.j2` |
| WebRTC viewer (development) | `client/viewer.html` |
| ESP32 firmware | `CameraWebServer/CameraWebServer.ino` |

## Conventions

- Ansible tasks use fully-qualified collection names (`ansible.builtin.*`)
- Shell scripts in templates use `set -euo pipefail` and log with timestamps
- Handlers are systemd-native; changes auto-trigger `daemon-reload` + service restart
- Latency modes: `low` (~1s GOP), `ultra` (~0.5s), `ultra_plus` (~0.25s) — set via `LATENCY_MODE` variable
