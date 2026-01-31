# TrainCam Network Requirements

This document describes the network configuration needed for TrainCam to function.

## WiFi Network

All TrainCam devices connect to a dedicated WiFi network:

| Setting | Value |
|---------|-------|
| SSID | _(your network name)_ |
| Password | _(your password)_ |

**Note:** The ESP32 firmware has placeholder credentials in `CameraWebServer/CameraWebServer.ino` — edit before uploading. The Pi uses standard wpa_supplicant configuration.

## Required Ports

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 8554 | TCP | RTSP | Video ingest and playback (MediaMTX) |
| 8889 | TCP | HTTP | WebRTC/WHEP endpoint (MediaMTX) |
| 8080 | TCP | HTTP | Static file server (viewer.html) |
| 22 | TCP | SSH | Ansible deployment access |

## mDNS / Service Discovery

TrainCam uses mDNS (Avahi/Bonjour) for hostname resolution. This works on:
- Home WiFi networks
- iPhone/Android hotspots
- Any local network (no internet required)

| Hostname | Device | Purpose |
|----------|--------|---------|
| `traincam1.local` | Onboard camera (Pi Zero W) | **Primary URL — use this everywhere** |
| `traincam.local` | ESP32 camera (planned) | ESP32 camera unit |

**Viewer URL:**
```
http://traincam1.local:8080/viewer.html
```

### Pi mDNS

Raspberry Pi OS has Avahi (mDNS) enabled by default. The Pi is addressable at `<hostname>.local`.

### ESP32 mDNS

**Status:** Not yet implemented (see `issues/1.md`)

When implemented, the ESP32 will advertise itself as `traincam.local` on the network.

## Network Topology

```
traincameranet (WiFi AP)
       │
       ├─── traincam1.local (Pi Zero W - onboard camera)
       │         │
       │         ├── RTSP: rtsp://traincam1.local:8554/traincam
       │         ├── WHEP: http://traincam1.local:8889/whep/traincam
       │         └── Viewer: http://traincam1.local:8080/viewer.html
       │
       └─── display.local (Pi 5 - receiver)
                 │
                 └── Chromium → http://traincam1.local:8080/viewer.html
```

## Viewer URL Parameters

The WebRTC viewer (`viewer.html`) accepts URL parameters for network flexibility:

| Parameter | Example | Description |
|-----------|---------|-------------|
| `whepPort` | `?whepPort=8889` | Override WHEP port (default: 8889) |
| `whepBase` | `?whepBase=http://192.168.1.100:8889` | Override entire WHEP base URL |

### Examples

```
# Default (same host as viewer)
http://traincam1.local:8080/viewer.html

# Explicit WHEP server
http://traincam1.local:8080/viewer.html?whepBase=http://relay.local:8889

# From a different network segment
http://192.168.1.50:8080/viewer.html?whepBase=http://192.168.1.50:8889
```

## Firewall Considerations

If running a firewall on the Pi, allow these ports:

```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 8080/tcp  # Viewer
sudo ufw allow 8554/tcp  # RTSP
sudo ufw allow 8889/tcp  # WebRTC/WHEP
sudo ufw allow 5353/udp  # mDNS
```

## Troubleshooting

### mDNS not resolving

If `traincam1.local` doesn't resolve:

1. Ensure Avahi is running: `systemctl status avahi-daemon`
2. Check hostname: `hostname` on the Pi should return `traincam1`
3. Use IP address as fallback: `ip addr show wlan0`

### WiFi connection issues

On the Pi:
```bash
# Check connection status
nmcli device wifi list
nmcli connection show

# Reconnect
nmcli connection up traincameranet
```

On ESP32:
- Check Serial output for connection status
- Verify SSID/password match exactly (case-sensitive)
- Ensure `WiFi.setSleep(false)` is set for reliable streaming

### Port conflicts

If MediaMTX fails to start:
```bash
# Check what's using ports
sudo lsof -i :8554
sudo lsof -i :8889
```
