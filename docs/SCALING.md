# Scaling TrainCam to Multiple Camera Units

This guide explains how to add additional camera units to your layout.

## Adding a New Camera

### 1. Prepare the Hardware

Set up a new Raspberry Pi Zero W with:
- Raspberry Pi OS (Bookworm or later)
- Camera module connected
- WiFi configured to connect to `traincameranet`

### 2. Set a Unique Hostname

On the new Pi:

```bash
sudo hostnamectl set-hostname traincam2
sudo reboot
```

The Pi will now be accessible as `traincam2.local`.

### 3. Update Inventory

Add the new camera to `inventory`:

```ini
[traincam]
traincam1.local ansible_user=train
traincam2.local ansible_user=train
```

### 4. (Optional) Per-Camera Variables

Create host-specific variables in `host_vars/traincam2.local.yml`:

```yaml
---
# Different resolution for this camera
traincam_width: 640
traincam_height: 480
traincam_fps: 30
```

### 5. Deploy

```bash
# Deploy to all cameras
ansible-playbook -i inventory traincam.yml

# Or deploy to just the new one
ansible-playbook -i inventory traincam.yml --limit traincam2.local
```

### 6. Access the New Camera

```
http://traincam2.local:8080/viewer.html
```

## Camera Naming Convention

| Hostname | Location | Notes |
|----------|----------|-------|
| `traincam1.local` | Lead locomotive | Primary engineer's view |
| `traincam2.local` | Caboose/rear car | Rear-facing view |
| `traincam3.local` | Yard camera | Fixed position |

## Multi-Camera Viewer

To view multiple cameras, open multiple browser tabs or create a dashboard page.

Example multi-view HTML (save as `multi-viewer.html`):

```html
<!DOCTYPE html>
<html>
<head><title>TrainCam Multi-View</title></head>
<body style="margin:0; display:flex; flex-wrap:wrap;">
  <iframe src="http://traincam1.local:8080/viewer.html" 
          style="width:50%; height:50vh; border:none;"></iframe>
  <iframe src="http://traincam2.local:8080/viewer.html" 
          style="width:50%; height:50vh; border:none;"></iframe>
</body>
</html>
```

## Network Considerations

Each camera needs:
- Unique hostname (`traincam1`, `traincam2`, etc.)
- Same WiFi network (`traincameranet`)
- Sufficient WiFi bandwidth (~2-5 Mbps per camera at 720p)

For more than 3-4 cameras, consider:
- 5GHz WiFi for higher bandwidth
- Dedicated WiFi access point for cameras
- Reducing resolution/framerate on some cameras

## Ansible Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `traincam_width` | 1280 | Video width in pixels |
| `traincam_height` | 720 | Video height in pixels |
| `traincam_fps` | 24 | Frames per second |
| `LATENCY_MODE` | ultra_plus | Latency preset (low/ultra/ultra_plus) |
| `traincam_awbgains` | "1.00,1.12" | Auto white balance gains |

See `group_vars/traincam.yml` for all available options.
