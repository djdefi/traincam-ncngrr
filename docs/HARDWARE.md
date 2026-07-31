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

> **Not every bank does this, and it is the hardest spec to satisfy.**
> "Pass-through charging" on the box usually means only that the bank *can*
> charge and output at the same time. It does not promise the output stays up
> when the input goes away. Many banks drop the rail for tens of milliseconds
> while they switch from charge mode to discharge mode, which brown-outs the Pi
> — a Zero has very little bulk capacitance to ride it out. A bank can run the
> Pi happily for hours on its cells and still fail this. Measured 2026-07-31:
> the bank fitted at the time rebooted the Pi four times out of four when its
> input was pulled, two of those hard enough to crash during early boot, and
> `vcgencmd get_throttled` never once reported undervoltage first. What you want
> is sometimes sold as "UPS mode" or "uninterruptible"; it is rarely stated, so
> step 2 of *Before Installing in a Car* is the arbiter, not the marketing.

**Specs:**
- Small form factor (fits in train car)
- Pass-through charging support
- **Uninterruptible output when input is removed** (test it; see above)
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
2. Verify the battery bank supports simultaneous charge and output without resetting when track power is removed and restored. Watch `/proc/sys/kernel/random/boot_id` across the gap, not uptime and not the LEDs — if that value changes, the Pi rebooted and the bank does not buffer. Test escalating gaps (a ~0.5s tap, 2s, 10s, 30s); the short ones matter most, because a switch gap is far shorter than a dead section. Note that undervoltage gives no warning: `get_throttled` stayed `0x0` right up to the moment of death in every failure observed so far.
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
| Purple/magenta image | NoIR module using the IR-filtered tuning | Point `traincam_tuning_source` at the `*_noir.json` for that sensor |
| Green/cyan image | IR-filtered module using the NoIR tuning | The reverse — use the plain `*.json` |
| Soft AND washed out, even with correct tuning | NoIR module in visible light | Physics, not config — see "NoIR is the wrong module for daylight" below |
| Camera "not detected" after a swap | Third-party sensor invisible to `camera_auto_detect`, or a cable that does not fit | Set `traincam_camera_overlay` — see "Swapping the camera module" below |
| Field of view much narrower than the lens | libcamera chose a cropped sensor mode to match the output aspect | Pin the mode — see "Check the sensor mode after any camera change" |
| Dark, noisy, or smeared on a dim layout | Unbinned sensor mode, ¼ the light per pixel | Same — pin the full-FOV binned mode |

## NoIR is the wrong module for daylight

**Both modules used here have been NoIR.** The IMX219 fitted Jul 2026 is one
too, so this still applies.

The module has no IR-cut filter. The `*_noir.json` tuning corrects the colour
matrix but it cannot undo the two physical costs, and no config setting will:

- **Washed out.** Infrared floods every photosite. The tuning rebalances the
  result; it cannot remove the light that already landed.
- **Soft.** IR focuses at a different plane than visible light, so the IR
  component lands defocused on top of the sharp visible image.

NoIR modules exist for night vision with an IR illuminator. For a lit layout an
IR-filtered module is the correct part, and swapping is the only real fix.

**How bad it is depends entirely on the lighting.** Incandescent and halogen are
blackbody radiators: a ~2800K filament emits more power in near-IR than in
visible, and halogen floods more still. They are the worst case. Fluorescent is
a line spectrum and modern LED emits almost no IR, so under those a NoIR module
with the `_noir` tuning can be close to fine.

**The Aug 2026 venue is mostly incandescent/halogen flood.** So this is the bad
case, and no software setting fixes it: Bayer dyes are largely transparent above
~700nm, which means IR lands in R, G and B at similar strength. That is a
common-mode pedestal, and per-channel gains are multiplicative — you cannot
subtract a common term by multiplying. This is exactly why IR-cut filters exist
in hardware instead of in software.

**Telling them apart, no tools:** point a TV remote at the lens and hold a
button. On the stream, a NoIR module shows the remote's LED as an obvious bright
white/violet dot. An IR-filtered module shows nothing at all.

**Telling them apart by measurement**, which is the reliable way — the eye gets
this backwards, because a correct rendering looks green immediately after a
magenta one, and any coloured room lighting defeats judgement entirely.

> **Measure in the video path. Never `rpicam-jpeg`.**
> The still and video pipelines converge on different white balance. Byte-
> identical options on one scene measured 1.046/1.032 through `rpicam-jpeg` and
> 0.785/0.809 through `rpicam-vid`. An earlier version of this page recommended
> `rpicam-jpeg` here, and following it produced a confident, wrong conclusion
> about which tuning file this module needs. Use `--codec mjpeg`:

```bash
sudo systemctl stop traincam
for t in imx219 imx219_noir; do
  rpicam-vid --nopreview -t 3000 --codec mjpeg --width 1280 --height 720 \
    --mode 1640:1232 --segment 1 -o /tmp/$t-%03d.jpg \
    --tuning-file /usr/share/libcamera/ipa/rpi/vc4/$t.json
done
sudo systemctl start traincam
```

Sample a genuinely neutral surface (white trim, a sheet of paper) and take the
channel ratios. Neutral is `R/G = B/G = 1.0`; above 1 is magenta, below is
green. Measured here in the video path: `imx219.json` gave 1.610/1.356,
`imx219_noir.json` gave 0.791/0.838.

**R and B elevated *together* is the IR signature** — coloured room lighting
would push one channel much harder than the other.

## White balance must be recalibrated at the venue

`imx219_noir.json` ships `rpi.awb = {"bayes": 0}`. Bayesian AWB is switched off
outright: there is no `ct_curve`, no `priors`, and no `modes` dict. Three
consequences, all confirmed by measurement:

- **`--awb` is a no-op** under this tuning. All seven modes measure identically,
  because the modes dict it would select from does not exist.
- libcamera falls back to **grey-world** AWB, which depends purely on scene
  statistics. That is why the still and video paths disagree: different sensor
  mode and downscale, different statistics.
- So `traincam_awb_gains` is not a workaround — it is the only white balance
  control that exists here.

The colour matrices are fine, though: the `_noir` file carries 8 CCMs spanning
2498–8575K, reaching further into tungsten than `imx219.json`'s 2860K. libcamera
back-derives colour temperature from manual gains (locked gains of `0.99,2.23`
reported `ColourTemperature: 2706`) and picks the right matrix, so no CCM
override is needed.

Because the lock is a fixed number, **it is only correct for the light it was
measured under**. Evidence it does not travel: with gains unchanged, one room
measured 0.985/1.094 in the evening and 1.152/1.114 the next morning.

Use the helper rather than doing this by hand:

```bash
./scripts/calibrate_awb.py measure   # white paper FILLING the frame, venue lighting
# paste the printed traincam_awb_gains into group_vars/traincam.yml
ansible-playbook -i inventory traincam.yml
./scripts/calibrate_awb.py verify    # normal scene; wants R/G and B/G near 1.00
```

The card must fill the frame because grey-world assumes the frame averages to
grey. Both commands stop the stream and restart it on exit, including on
failure.

**If there is no time to calibrate at the venue, clear `traincam_awb_gains`
rather than shipping a lock from another room.** Grey-world auto is at least
self-correcting; a wrong fixed lock is not.

## Swapping the camera module

`camera_auto_detect=1` probes **only** the official Raspberry Pi sensors:
`ov5647` (v1), `imx219` (v2), `imx477` (HQ), `imx708` (v3). Anything else —
Arducam's `imx519` 16MP, `ov64a40` 64MP, the Pivariety low-light boards — is
invisible to it, and the symptom is identical to a dead ribbon cable. Some
third-party clones of supported sensors also fail the probe.

1. **Power off.** Never swap a CSI cable live: the ribbon carries 3.3 V and I²C,
   and the contacts bridge against each other on the way in.
2. **Use the cable that fits the new module**, not the one that works today. A
   Pi Zero 2 W is narrow 22-pin at its end, but the module end varies — the
   OV5647 here uses narrow→wide (15-pin), which physically will not fit a module
   with a 22-pin socket. A mismatched cable is a plausible reason a module
   "was never detected". A 22-to-22 cable has shipping lead time; check first.
3. Boot and check: `rpicam-vid --list-cameras`
4. If it lists nothing, name the sensor explicitly in `group_vars/traincam.yml`
   and re-deploy, then reboot:
   ```yaml
   traincam_camera_overlay: imx219
   ```
   The deploy asserts the `.dtbo` exists, so a typo fails the run rather than
   the camera, and it sets `camera_auto_detect=0` to match — the explicit
   overlay and the probe must not both run. Clearing the variable reverses
   both. See what this Pi has:
   `ls /boot/firmware/overlays/ | grep -E 'imx|ov[0-9]'`
5. Read `dmesg` — the three outcomes are unambiguous, and this split is the
   whole diagnostic:
   | `sudo dmesg \| grep -i imx219` | Meaning |
   |---|---|
   | `failed to read chip id` | Driver loaded, sensor unreachable: cable, orientation, or dead module |
   | Registers / dependency-cycle lines | Working |
   | No mention at all | The overlay did not load |
6. **Set the matching tuning**, or the colour will be wrong in a new way. Do
   not guess — shoot the same scene through both and pick, it takes two
   minutes:
   ```yaml
   traincam_tuning_source: /usr/share/libcamera/ipa/rpi/vc4/imx219.json       # IR-filtered
   # traincam_tuning_source: /usr/share/libcamera/ipa/rpi/vc4/imx219_noir.json  # NoIR
   ```
7. **Check which sensor mode libcamera picked** — see below. This is the step
   that is easiest to skip and costs the most.

## Check the sensor mode after any camera change

libcamera picks a sensor mode to match the *aspect ratio* of the requested
output, which is often not the mode you want. On the IMX219 at 1280x720 it
chooses 1920x1080 — an **unbinned crop** of the 3280x2464 array, measured at
left 688, top 700. That is 58% of the sensor width: a keyhole instead of the
room, and a quarter of the light per pixel because nothing is binned.

`--mode 1640:1232` in `traincam_extra_opts` pins the full-FOV 2×2-binned mode
instead. Confirm which one is live — this reads the hardware, not the config:

```bash
v4l2-ctl -d /dev/v4l-subdev0 --get-subdev-fmt | grep -i width
v4l2-ctl -d /dev/v4l-subdev0 --get-subdev-selection target=crop
```

Full FOV reads `crop, Left 8, Top 8, Width 3280, Height 2464`. Anything else is
a crop.

Binning matters here more than it looks. Measured in a *lit* room at 33–41 lux
the AGC was already pegged at its ceiling — 66502 µs at gain 5.95 — and a layout
with tunnels is darker. Binning is 4× the photons per output pixel. The same
conclusion came out of testing the OV5647's unbinned 1920x1080 mode, which was
rejected as visibly darker and noisier.
