# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TrainCam is a live camera streaming system for model railroads. A tiny camera mounted on a moving train streams video over local WiFi, powered from DCC track power. Two hardware platforms are supported: Raspberry Pi Zero W (primary) and ESP32-S3 XIAO Sense.

## Commands

```bash
# Deploy to Raspberry Pi (requires SSH access to target)
ansible-playbook -i inventory traincam.yml

# Run all tests (38 bash tests across 3 test files)
./tests/run_tests.sh

# Run a single test file
bash tests/test_latency_modes.sh
bash tests/test_config_parsing.sh
bash tests/test_network_config.sh

# Lint everything (ansible-lint + shellcheck)
./scripts/lint.sh

# Lint individually
ansible-lint
shellcheck --shell=bash --exclude=SC1091,SC2086 ansible/roles/traincam/templates/*.sh.j2

# Build iOS app (requires Xcode + macOS)
xcodebuild -project ios/TrainCam/TrainCam.xcodeproj -scheme TrainCam -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run iOS tests
xcodebuild -project ios/TrainCam/TrainCam.xcodeproj -scheme TrainCam -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Architecture

**Streaming pipeline (Pi):**
```
rpicam-vid (H.264) → MediaMTX (RTSP ingest) → WebRTC/RTSP out
                                                    ↓
                                          viewer.html (port 8080)
```

**Key ports:** 8080 (HTTP viewer), 8554 (RTSP), 8889 (WebRTC/WHEP), 8555 (WebRTC UDP), 8556 (WebRTC TCP)

**Provisioning:** A single Ansible role (`ansible/roles/traincam/`) deploys everything. The entry playbook is `traincam.yml`. All runtime config is templated to `/etc/traincam/stream.conf` on the Pi. Three systemd services are created: `traincam`, `mediamtx`, and `traincam-viewer`.

**ESP32 firmware:** Arduino sketch in `CameraWebServer/` for Seeed Studio XIAO ESP32S3. Compiled and uploaded via Arduino IDE.

**iOS App:** Native SwiftUI client in `ios/TrainCam/`. Discovers cameras via mDNS/BLE, displays MJPEG (ESP32) and WebRTC/WHEP (Pi) streams.

## Key Files

| Purpose | Location |
|---------|----------|
| Main Ansible playbook | `traincam.yml` |
| Role variables (video, ports, paths) | `group_vars/traincam.yml` |
| Ansible role tasks | `ansible/roles/traincam/tasks/main.yml` |
| Stream capture script template | `ansible/roles/traincam/templates/stream.sh.j2` |
| RTSP publish script template | `ansible/roles/traincam/templates/publish.sh.j2` |
| MediaMTX config template | `ansible/roles/traincam/templates/mediamtx.yml.j2` |
| WebRTC viewer (standalone) | `client/viewer.html` |
| ESP32 firmware | `CameraWebServer/CameraWebServer.ino` |
| iOS app entry point | `ios/TrainCam/TrainCam/TrainCamApp.swift` |
| iOS camera discovery | `ios/TrainCam/TrainCam/CameraDiscovery.swift` |
| iOS stream viewer | `ios/TrainCam/TrainCam/MJPEGStreamView.swift` |

## Conventions

- Ansible tasks use fully-qualified collection names (`ansible.builtin.*`)
- Shell scripts and templates use `set -euo pipefail` and log with timestamps
- Handlers are systemd-native; config changes auto-trigger `daemon-reload` + service restart
- Latency modes control keyframe intervals: `low` (~1s GOP = FPS), `ultra` (~0.5s = FPS/2), `ultra_plus` (~0.25s = FPS/4) — set via `LATENCY_MODE` in `group_vars/traincam.yml`
- ShellCheck exclusions for templates: SC1091 (sourced files) and SC2086 (word splitting for Jinja vars)
- CI runs lint (non-blocking) and tests on push/PR to main
- iOS app uses SwiftUI with iOS 17.0 deployment target, dark mode forced, no third-party dependencies
- Camera discovery uses NWBrowser (mDNS) and CoreBluetooth (BLE) with timeout-based scanning
