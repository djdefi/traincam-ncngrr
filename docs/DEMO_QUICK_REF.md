# Demo Quick Reference

## Current Status: ✅ READY

**The only URL you need:**
```
http://traincam1.local:8080/viewer.html
```

Add this to your iPhone home screen for one-tap access.

---

## Network

The layout has a real router: **`traincameranet`**. The Pi auto-connects to it
and that is the normal path — nothing to turn on.

**iPhone hotspot is the fallback only**, for when the layout router is down or
you are demoing away from the layout. If you use it, the hotspot SSID/password
must already be stored in the Pi's NetworkManager — it cannot be added on the
day without SSH access to a Pi you can't reach. Set it up in advance or not at all.

---

## At the Meetup

1. **Power on Pi Zero** — wait ~30 seconds
2. **Open Safari:** `http://traincam1.local:8080/viewer.html`

The big screen (Pi 5 kiosk) starts on its own — see `docs/RECEIVER.md`.

**Works offline — no internet required!**

---

## Add to Home Screen (One-Tap Access)

1. Open the URL in Safari
2. Tap **Share** button (square with arrow)
3. Tap **"Add to Home Screen"**
4. Name it **TrainCam** → tap **Add**

---

## Demo Script (2 minutes)

> "This is TrainCam — a camera that rides on the train and shows you the engineer's view."
>
> *[Show phone with live feed]*
>
> "The camera is in that freight car, running on a battery pack that lasts about five hours."
>
> "It sends video over WiFi, and we can watch it on any screen — phone, tablet, TV."
>
> *[Move train, show live video responding]*
>
> "Everything is open source. We're building this for the club so visitors can experience the layout from the train's perspective."

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Pi not connecting | Check it's on `traincameranet`, not a stale network. Wait 30 sec. |
| Page won't load | Make sure you're on the same WiFi as the Pi |
| Video stuck on "connecting" | Refresh the page |
| Black video | Check camera ribbon cable |

---

## Technical Details

| What | Value |
|------|-------|
| Hostname | `traincam1.local` (via Avahi/mDNS) |
| Viewer | `http://traincam1.local:8080/viewer.html` |
| RTSP | `rtsp://traincam1.local:8554/traincam` |
| SSH | `ssh train@traincam1.local` |
