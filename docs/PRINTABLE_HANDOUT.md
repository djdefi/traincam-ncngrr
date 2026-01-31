# TrainCam — See What the Engineer Sees

## What Is It?

A tiny camera rides on a model train and streams the engineer's view live to any screen.

```
   🚂 Camera on Train  ───►  📡 WiFi  ───►  📺 Your Phone/TV
```

**Powered by the track** — no batteries to swap!

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         POWER CHAIN                                         │
│                                                                             │
│   DCC Track     Bridge        Buck          USB           Camera            │
│   ~14V AC   →   Rectifier  →  Converter  →  Battery   →   Unit              │
│                 (AC→DC)       (14V→5V)      (buffer)      (Pi Zero          │
│                                                            or ESP32)        │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Step | Component | What It Does |
|------|-----------|--------------|
| ① | Bridge Rectifier | Converts track AC to DC |
| ② | Buck Converter | Steps 14V down to safe 5V |
| ③ | USB Battery | Buffers power through dirty track/gaps |
| ④ | Camera Unit | Streams HD video over WiFi |

---

## Components on Display

**Touch and examine each part!**

```
┌───────────┐   ┌───────────┐   ┌───────────┐   ┌───────────┐   ┌───────────┐
│  BRIDGE   │   │   BUCK    │   │    USB    │   │  PI ZERO  │   │  ESP32    │
│ RECTIFIER │   │ CONVERTER │   │  BATTERY  │   │ + CAMERA  │   │   XIAO    │
│           │   │           │   │           │   │           │   │           │
│  (small   │   │  (blue    │   │  (small   │   │ (credit   │   │ (postage  │
│   black   │   │   PCB)    │   │  power    │   │   card    │   │  stamp    │
│   chip)   │   │           │   │   bank)   │   │   size)   │   │   size!)  │
└───────────┘   └───────────┘   └───────────┘   └───────────┘   └───────────┘
     ①               ②               ③               ④              ④alt
```

### Size Comparison
```
Pi Zero + Camera:  ████████████████████  65mm x 30mm
ESP32-S3 XIAO:     █████                 21mm x 17mm  ← Fits anywhere!
```

---

## Why Each Part?

| Part | Why We Need It |
|------|----------------|
| **Rectifier** | Track power is AC-like; electronics need DC |
| **Buck Converter** | Track is ~14V, Pi needs exactly 5V (too much = 💥) |
| **Battery Bank** | Dirty track = power gaps; battery bridges the gaps |
| **Pi Zero** | Runs Linux, streams H.264 video, WebRTC for low latency |
| **ESP32** | Even smaller! Built-in camera, simpler but less features |

---

## Quick Questions

**Q: Why not just use batteries?**
> Batteries run out! Track power + battery buffer = runs forever.

**Q: How far does WiFi reach?**
> Easily covers a room-sized layout.

**Q: Can I build one?**
> Yes! It's open source. Scan the QR code below.

---

## Get Involved

**Scan for code & docs:**

![QR Code to GitHub repo](../qr-repo.jpg)

**GitHub:** github.com/djdefi/traincam-ncngrr  
**Contact:** Issues & PRs welcome!

---

## What's Next?

- [ ] Multiple cameras (cab cam, yard cam, rear view)
- [ ] Recording favorite runs
- [ ] Audio from the train
- [ ] Mobile app viewer

---

*Open source — built by hobbyists, for hobbyists*
