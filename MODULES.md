# YumiOS-Klipper-V2 — Modules Fork-Locked

## Strategy

All modules source from **Yumi-Lab forks** on branch **`yumi-stable`**.

- **`master` branch** (fork only) = auto-synced from upstream weekly (sync-upstream.yml)
- **`yumi-stable` branch** = validated state, used for builds, updated manually after testing

This ensures **zero breaking changes** from upstream without losing security patches.

---

## Modules to Copy from YumiOS Original (19 modules)

| Module | Source | Role |
|--------|--------|------|
| klipper | `Yumi-Lab/klipper@yumi-stable` | Klipper firmware core |
| moonraker | `Yumi-Lab/moonraker@yumi-stable` | API server + update manager |
| klipperscreen | `Yumi-Lab/KlipperScreen@yumi-stable` | Touch UI |
| mainsail | `Yumi-Lab/mainsail@yumi-stable` | Web UI |
| crowsnest | `Yumi-Lab/crowsnest@yumi-stable` | Webcam streaming |
| sonar | `Yumi-Lab/sonar@yumi-stable` | WiFi keepalive daemon |
| mainsail-config | `Yumi-Lab/mainsail-config@yumi-stable` | Default printer.cfg templates |
| timelapse | `Yumi-Lab/moonraker-timelapse@yumi-stable` | Timelapse plugin for Moonraker |
| tmc-autotune | `Yumi-Lab/klipper_tmc_autotune@yumi-stable` | TMC driver auto-tuning |
| camera-streamer | `Yumi-Lab/camera-streamer@yumi-stable` | Camera streaming (alt to crowsnest) |
| ustreamer | `Yumi-Lab/ustreamer@yumi-stable` | Lightweight MJPEG streaming |
| smartpad | YumiOS original | SmartPad hardware tweaks |
| yumi-sync | YumiOS original | Log sync daemon |
| yumi-config | YumiOS original | First-boot wizard |
| usb-automount | YumiOS original → `Yumi-Lab/yumi-automount` | USB auto-mount service |
| mcu-rpi | YumiOS original | RPi MCU support |
| cpu_governor | YumiOS original | Fixed 912 MHz governor for SmartPad |
| armbian_net | CustomPiOS original | Network configurator |
| base | CustomPiOS original | Base OS setup |

---

## Modules to Create (3 modules)

| Module | Purpose |
|--------|---------|
| yumi-plymouth | Cinnamoroll boot theme + logo |
| yumi-klipper-screen | Entry point for future UI replacement (currently stub) |
| yumi-automount | Rewritten from scratch (50 lines) |

---

## Fork Governance

Each fork follows this pattern:

```
Upstream (e.g., klipper3d/klipper)
    ↓ (pull via GitHub)
Yumi-Lab fork / master (auto-synced weekly)
    ↓ (manual PR review)
Yumi-Lab fork / yumi-stable (validated branch — used for YumiOS builds)
```

**sync-upstream.yml** runs every Monday 6 AM :
1. Fetches latest upstream commits
2. Merges into `master` (fork only)
3. Opens PR `master → yumi-stable` (requires manual validation)
4. YumiOS build waits for validation before pulling

---

## Update Flow

**Scenario: Klipper upstream releases v0.12.0 with critical bugfix**

1. **Monday 6 AM** : sync-upstream.yml detects new commit on upstream master
2. **Auto** : Merges into `Yumi-Lab/klipper@master`
3. **Auto** : Opens PR `master → yumi-stable` with changelog
4. **Manual** : DevOps reviews changelog + tests on SmartPad
5. **Manual** : Merge to `yumi-stable` OR close PR if issues detected
6. **Next build** : YumiOS pulls from `yumi-stable` → includes fix

**Risk mitigation** :
- PADs see no changes until `yumi-stable` is updated
- Moonraker update_manager compares against `yumi-stable` HEAD
- If PAD is at commit X and `yumi-stable` is still at X → no update notification

---

## Zero Hardcoding Rule

All module configs use **variables**, never hardcoded URLs:

### ✅ GOOD
```bash
# In src/modules/klipper/config
[ -n "$KLIPPER_REPO_SHIP" ] || KLIPPER_REPO_SHIP="${FORK_KLIPPER}"
[ -n "$KLIPPER_REPO_BRANCH" ] || KLIPPER_REPO_BRANCH="${YUMI_STABLE_BRANCH}"
```

### ❌ BAD
```bash
# DON'T DO THIS
KLIPPER_REPO_SHIP="https://github.com/Yumi-Lab/klipper.git"
KLIPPER_REPO_BRANCH="yumi-stable"
```

Variables are sourced from `src/.env.build` at build time.

---

## Testing Module After Fork-Pin

Each module must be tested to ensure :
1. Git remote points to Yumi-Lab fork
2. Moonraker recognizes the module in update_manager
3. Service starts correctly on boot

See **Phase 3 — VALIDATE** for hardware test protocol.
