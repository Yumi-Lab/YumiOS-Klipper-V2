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
| cpu_governor | YumiOS original | One fixed CPU frequency (`CPU_GOVERNOR_FREQ_KHZ`, 960 MHz) — cpufrequtils on Armbian, dietpi.txt on DietPi |
| armbian_net | CustomPiOS original | Network configurator (Armbian base only) |
| dietpi | YumiOS original | DietPi-SmartPi base → YumiOS (NetworkManager, OpenSSH, logs, zram, first run) |
| base | CustomPiOS original | Base OS setup |

---

## Modules to Create (3 modules)

| Module | Purpose |
|--------|---------|
| yumi-plymouth | Cinnamoroll boot theme + logo |
| yumi-klipper-screen | Entry point for future UI replacement (currently stub) |
| yumi-automount | Rewritten from scratch (50 lines) |

---

## Base images

| Config | Base | Module chain |
|--------|------|--------------|
| `armbian/smartpi-debian` | `Yumi-Lab/SmartPi-armbian` v1.7.0, Bookworm server | `base(udev_fix,armbian(armbian_net,…))` |
| `armbian/smartpi-trixie` | `Yumi-Lab/SmartPi-armbian` v1.8.0-rc1, Trixie server | same |
| `dietpi/smartpi-trixie` | `Yumi-Lab/DietPi-SmartPi` v1.8.0-rc5, Trixie (DietPi conversion of the SmartPi-armbian server image) | `base(udev_fix,dietpi,armbian(…))` — no `armbian_net` |

`config/dietpi/default` sources `config/armbian/default` (same SmartPi ONE hardware, U-Boot,
kernel, `armbianEnv.txt`, FAT `/boot`) and only overrides the download origin, `BASE_DISTRO`,
`ARMBIAN_DEPS` (no `armbian-config` on DietPi) and the module chain.

### What the `dietpi` module puts back

The DietPi installer reshapes the userland of the Armbian server image. The module runs right
after `base`, before `armbian`, and restores what the YumiOS stack relies on:

| DietPi state | YumiOS needs | Module action |
|---|---|---|
| ifupdown + wpa_supplicant, no NetworkManager | NM (sonar dispatcher, KlipperScreen network panel) | installs NM, `/etc/network/interfaces` keeps `lo` only |
| Dropbear | OpenSSH (SAV reverse tunnel, sftp) | purges Dropbear, installs OpenSSH, per-device host keys on first boot (`yumi-ssh-hostkeys.service`) |
| `/var/log` = 50 MB tmpfs (dietpi-ramlog) | on-disk logs + rsyslog | drops the fstab line, disables ramlog |
| swapfile on the SD card at first boot | zram (Armbian parity) | `zram-tools`, `AUTO_SETUP_SWAPFILE_SIZE=0` |
| automated first run: dietpi-update + dietpi-software + reboot, root autologin on tty1 | the YumiOS firstboot wizard | `AUTO_SETUP_AUTOMATED=0`, `.install_stage=2` right after `dietpi-firstboot` (drop-in) |
| hostname `DietPi`, gb keyboard, London timezone | `BASE_OVERRIDE_HOSTNAME`, us, UTC | `dietpi.txt` preseeds via `yumi-dietpi-txt` |
| `verbosity=4` in `armbianEnv.txt` | 1 (Plymouth splash) | rewrites the key |
| cpufrequtils ignored, `dietpi-preboot` applies `dietpi.txt` | fixed 960 MHz | `cpu_governor` writes `CONFIG_CPU_*` (performance, min = max) |

`dietpi-firstboot` itself is kept: hostname, root password (`BASE_USER_PASSWORD`), locale,
timezone, machine-id, and `dietpi-fs_partition_resize` expands the root filesystem.

## Initramfs — built at image build time

`update-initramfs -u` without `-k` is a **silent no-op** in the build chroot: the bases ship no
`/var/lib/initramfs-tools` record and `uname -r` is the CI runner kernel, so nothing is done
and the command exits 0. Images built until 2026-06 therefore shipped the untouched base
initrd and the firstboot wizard rebuilt it on the pad — the step behind un-bootable pads
(`Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00`, i.e. the
initramfs could not exec `run-init` after `init-bottom`).

The `smartpad` module now runs `update-initramfs -u -k <installed kernel>` and fails the build
unless `lsinitramfs` shows `run-init`, the klibc loader it links against, the Plymouth theme
and `two-step.so`, and unless `/boot/uInitrd` wraps exactly that initrd. `bootlogo=true` is
set at build time; the wizard no longer touches the initramfs or the boot logo.

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
