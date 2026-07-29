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

**Option A: Raspberry Pi Zero 2 W + Camera Module**
- Pi Zero 2 W running 64-bit Raspberry Pi OS
- Camera Module v2 or v3 (CSI connector)
- Power: 5V via micro USB from battery bank
- Runs `rpicam-vid` for H.264 streaming
- Provisioned headless: no desktop, VNC, HDMI, audio, or Bluetooth

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

## Before Installing in a Car

1. Set the buck converter to 5.1V before connecting a camera, then confirm it stays stable under camera load.
2. Verify the battery bank supports simultaneous charge and output without resetting when track power is removed and restored.
3. Run the complete camera for 30 minutes and confirm `vcgencmd get_throttled` reports `0x0`.
4. Insulate every exposed conductor, add strain relief, and keep the converter and camera ventilated.
5. Repeat the test from wheel pickups on the layout before securing the car body.
6. Measure 5V input current while a viewer is connected; size the converter and battery from the measured load, not a module's advertised maximum.

The Pi role disables hardware and services that the headless camera does not
use. A reboot is required after the first deployment. It deliberately leaves
WiFi, CPU clocks, resolution, frame rate, and keyframe timing unchanged.

## Troubleshooting

| Problem | Possible Cause | Fix |
|---------|---------------|-----|
| Pi reboots randomly | Power interruptions | Check wheel pickup contacts, add capacitor buffer |
| No power at all | Bridge rectifier failed | Check rectifier with multimeter |
| Pi won't boot | Buck converter voltage wrong | Verify 5V output with multimeter |
| Overheating | Buck converter undersized | Use higher efficiency/capacity buck |
| Weak WiFi | Camera position | Ensure antenna not blocked by metal |
| Purple/magenta image | NoIR module using the IR-filtered tuning | Set `traincam_tuning_file` to `ov5647_noir.json` (see `group_vars/traincam.yml`) |
| Soft AND washed out, even with correct tuning | NoIR module in visible light | Physics, not config — see "NoIR is the wrong module for daylight" below |
| Camera "not detected" after a swap | Third-party sensor invisible to `camera_auto_detect` | Set `traincam_camera_overlay` — see "Swapping the camera module" below |

## NoIR is the wrong module for daylight

The fitted OV5647 has no IR-cut filter. `ov5647_noir.json` corrects the colour
matrix (measured in 388f808: U 143.3 → 123.9, V 148.4 → 124.8 against a neutral
128) but it cannot undo the two physical costs, and no config setting will:

- **Washed out.** Infrared floods every photosite. The tuning rebalances the
  result; it cannot remove the light that already landed.
- **Soft.** IR focuses at a different plane than visible light, so the IR
  component lands defocused on top of the sharp visible image.

NoIR modules exist for night vision with an IR illuminator. For a lit layout an
IR-filtered module is the correct part, and swapping is the only real fix.

**Telling them apart, no tools:** point a TV remote at the lens and hold a
button. On the stream, a NoIR module shows the remote's LED as an obvious bright
white/violet dot. An IR-filtered module shows nothing at all.

## Swapping the camera module

`camera_auto_detect=1` probes **only** the official Raspberry Pi sensors:
`ov5647` (v1), `imx219` (v2), `imx477` (HQ), `imx708` (v3). Anything else —
Arducam's `imx519` 16MP, `ov64a40` 64MP, the Pivariety low-light boards — is
invisible to it, and the symptom is identical to a dead ribbon cable. Some
third-party clones of supported sensors also fail the probe.

1. **Power off**, then swap the sensor board but **keep the ribbon cable that
   works today**. A Pi Zero 2 W needs the narrow 22-pin CSI cable, not the wide
   15-pin one that ships with most modules — reusing the known-good cable
   removes the most likely variable.
2. Boot and check: `rpicam-vid --list-cameras`
3. If it lists nothing, name the sensor explicitly in `group_vars/traincam.yml`
   and re-deploy, then reboot:
   ```yaml
   traincam_camera_overlay: imx219
   ```
   The deploy asserts the `.dtbo` exists, so a typo fails the run rather than
   the camera. See what this Pi has:
   `ls /boot/firmware/overlays/ | grep -E 'imx|ov[0-9]'`
4. If it still lists nothing after that, it is genuinely cable or hardware.
5. **Set the matching tuning**, or the colour will be wrong in a new way:
   ```yaml
   traincam_tuning_source: /usr/share/libcamera/ipa/rpi/vc4/imx219.json       # IR-filtered
   # traincam_tuning_source: /usr/share/libcamera/ipa/rpi/vc4/imx219_noir.json  # NoIR
   ```

An IMX219 is also a genuine image upgrade over the OV5647: its full-FOV binned
mode is 1640x1232, so a 1280x720 output is downsampled ~1.28x. The OV5647's
equivalent mode is 1296x972 — effectively 1:1 with the output, so there is no
supersampling to hide sensor softness.
