# Demo Quick Reference

## Current Status: ✅ READY

**The only URL you need:**
```
http://traincam1.local:8080/viewer.html
```

Add this to your iPhone home screen for one-tap access.

---

## iPhone Hotspot Setup

**Your phone hotspot:**
- **Name:** _(configure on your phone)_
- **Password:** _(configure on your phone)_

**Pi auto-connects to networks configured in wpa_supplicant.**

---

## At the Meetup

1. **Turn on hotspot:** Settings → Personal Hotspot → ON
2. **Power on Pi Zero** — wait ~30 seconds
3. **Open Safari:** `http://traincam1.local:8080/viewer.html`

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
> "The camera is in that freight car. It picks up power from the tracks — same power that runs the train — so no batteries to change."
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
| Pi not connecting | Wait 30 sec, keep Personal Hotspot screen open |
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
