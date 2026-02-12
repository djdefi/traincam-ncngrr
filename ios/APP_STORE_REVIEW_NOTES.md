# App Store Review Notes

## App Review Notes

> Paste the following into the **App Review Notes** field in App Store Connect.

---

RailCam is a free utility that discovers and displays live video from miniature cameras mounted on model railroad trains. It connects to two types of TrainCam hardware over the local WiFi network: ESP32 cameras (MJPEG streams) and Raspberry Pi cameras (WebRTC/WHEP streams).

**This app requires physical TrainCam camera hardware on the same local WiFi network to display live video.** Without a camera present, RailCam will launch normally and all UI and navigation is fully functional, but the camera list will be empty and no streams will play.

We recommend reviewing the included demo video (attached as an app preview or linked below) which shows RailCam operating with real TrainCam hardware. The video demonstrates camera discovery, live streaming, and the full user experience.

No account creation or sign-in is required. RailCam has no server backend — all communication stays on the local network between the iOS device and the camera hardware.

---

## Demo Information

### What reviewers will see without hardware

- The camera list screen in its empty state (no cameras found)
- The manual "Add Camera" dialog where an IP address can be entered
- All tab navigation, settings, and UI screens are accessible and functional

### What reviewers would see with hardware

- Cameras auto-discovered via mDNS (Bonjour) appearing in the camera list
- Live video streams from ESP32 (MJPEG) and Raspberry Pi (WebRTC) cameras
- Stream telemetry such as resolution, frame rate, and connection status

### Recommended demo video

Include a 30–60 second screen recording showing:

1. App launch and the camera list populating via auto-discovery
2. Tapping a discovered camera to open the live stream
3. The live video playing with visible telemetry/status indicators

Attach this as a review attachment in App Store Connect or provide a link in the review notes.

## Permissions Explained

| Permission | Usage | Required |
|---|---|---|
| **Local Network** | mDNS/Bonjour browsing (`_traincam._tcp`) to discover cameras on the local WiFi network, and HTTP/WebRTC connections to stream video from discovered cameras. | Yes |
| **Bluetooth** | BLE (Bluetooth Low Energy) scanning to discover nearby TrainCam cameras that advertise via BLE. This is an optional discovery method — the app functions fully without it using mDNS alone. | Optional |

Both permission prompts appear on first use of the respective feature. If the user denies Local Network access, camera discovery will not work but the user can still manually add cameras by IP address. If the user denies Bluetooth, only BLE-based discovery is disabled; mDNS discovery and all streaming features remain available.
