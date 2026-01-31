# TrainCam Hardware - Power Chain

The onboard camera runs on power harvested from the DCC track. This document describes the power chain from rails to camera.

## Power Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           POWER CHAIN                                       │
│                                                                             │
│   DCC Track    Truck        Bridge       Buck         USB Battery   Camera  │
│   Power     →  Pickups   →  Rectifier →  Converter →  Bank       →  Unit   │
│                                                                             │
│   ~14V AC      Wheels       AC → DC      DC → 5V      Buffer &      RPi    │
│   (NCE          contact      ~14V DC      USB out      charge       Zero W  │
│   PowerCab)     rails                                               + Cam   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. DCC Track Power

**Source:** NCE PowerCab (or compatible DCC system)

**Output:** ~14V AC (On3 scale, varies by DCC system and load)

**Notes:** DCC is AC-like (square wave), not pure DC. The bridge rectifier handles this.

### 2. Truck/Wheel Pickups

**Purpose:** Collect power from rails via wheel contact

**Implementation:**
- Metal wheels with electrical contact to trucks
- Wires from trucks routed through train car body
- Both rails used (common return)

**Tips:**
- Keep connections clean for reliable power
- Use multiple wheel pickups if possible for redundancy
- Flexible wire to allow truck pivoting

### 3. Bridge Rectifier

**Purpose:** Convert AC/DCC square wave to DC

**Specs:**
- Input: ~14V AC from track
- Output: ~12-14V DC (unregulated)
- Type: Full-wave bridge rectifier (4 diodes or integrated module)

**Common parts:**
- MB10S bridge rectifier (small, SMD)
- 2W10 bridge rectifier (through-hole)
- Any 1A+ rated bridge rectifier rated for 25V+

### 4. Buck Converter

**Purpose:** Step down ~14V DC to stable 5V DC

**Specs:**
- Input: 8-24V DC (handles track voltage variations)
- Output: 5V DC, 2A+ capable
- Efficiency: 90%+ preferred for heat management

**Common parts:**
- MP1584 module (small, cheap)
- LM2596 module (common, adjustable)
- Any 5V USB output buck converter

**Important:** Must provide stable 5V even with track voltage fluctuations (dirty track, load changes, etc.)

### 5. USB Battery Bank

**Purpose:** Buffer power and provide stable 5V to Pi

**Why a battery bank?**
- Buffers momentary power interruptions (dirty track, switch gaps)
- Provides stable 5V USB output
- Pass-through charging keeps it topped up while power is available
- Pi continues running briefly during power gaps

**Specs:**
- Small form factor (fits in train car)
- Pass-through charging support
- 5V 2A+ output capability
- 2000-5000mAh capacity (balance size vs runtime)

**Example:** Small USB power banks with pass-through charging (check specs)

### 6. Camera Unit

**Option A: Raspberry Pi Zero W + Camera Module**
- Pi Zero W (WiFi built-in)
- Camera Module v2 or v3 (CSI connector)
- Power: 5V via micro USB from battery bank
- Runs `rpicam-vid` for H.264 streaming

**Option B: ESP32-S3 + OV2640**
- Seeed Studio XIAO ESP32S3 Sense
- OV2640 camera (built-in on Sense module)
- Power: 5V via USB-C from battery bank
- Runs `CameraWebServer` sketch for MJPEG streaming

## Physical Installation

```
┌─────────────────────────────────────────────────────────────────┐
│                      TRAIN CAR LAYOUT                           │
│                                                                 │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │
│   │Rectifier│──│  Buck   │──│ Battery │──│ Pi Zero + Cam   │   │
│   └────┬────┘  │Converter│  │  Bank   │  │    (forward)    │   │
│        │       └─────────┘  └─────────┘  └─────────────────┘   │
│   ┌────┴────┐                                                   │
│   │  Truck  │ ← Wheel pickups                                   │
│   │ Pickups │                                                   │
│   └─────────┘                                                   │
└─────────────────────────────────────────────────────────────────┘
```

**Tips:**
- Mount camera at front of car for engineer's view
- Secure battery bank to prevent shifting
- Use hot glue or foam tape for component mounting
- Route wires to avoid interference with trucks
- Consider adding a power switch for easy on/off

## Troubleshooting

| Problem | Possible Cause | Fix |
|---------|---------------|-----|
| Pi reboots randomly | Power interruptions | Check wheel pickup contacts, add capacitor buffer |
| No power at all | Bridge rectifier failed | Check rectifier with multimeter |
| Pi won't boot | Buck converter voltage wrong | Verify 5V output with multimeter |
| Overheating | Buck converter undersized | Use higher efficiency/capacity buck |
| Weak WiFi | Camera position | Ensure antenna not blocked by metal |
