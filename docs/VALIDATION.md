# YumiOS-Klipper-V2 — Build & Validation

This document describes the multi-stage validation pipeline for YumiOS-Klipper-V2 fork-locked builds.

---

## Overview

The validation process ensures:
1. **Structure** — All modules and dependencies are correctly organized
2. **Syntax** — Build scripts and configurations are valid
3. **Build** — Docker image builds successfully (multi-arch)
4. **Boot** — Built images boot in QEMU and services start
5. **Fork-locked** — All components point to correct `yumi-stable` branches

---

## Stage 1: Structure & Syntax Validation (build.yml)

**Trigger**: Push to develop/yumi-stable, or PR

**Checks**:
- Module directories exist and contain proper structure
- All `.sh` files have valid bash syntax
- `src/.env.build` loads without errors
- Fork URLs are defined and not duplicated
- No hardcoded IPs or credentials

**Run locally**:
```bash
# Check module structure
ls -la src/modules/ | wc -l

# Validate bash syntax
bash -n src/modules/*/start_chroot_script
bash -n tests/*.sh

# Load environment
source src/.env.build
echo "YUMIOS_VERSION: $YUMIOS_VERSION"
echo "FORK_KLIPPER: $FORK_KLIPPER"
```

---

## Stage 2: Docker Build Validation (build.yml — docker-build-test job)

**Trigger**: After structure checks pass

**What it does**:
- Sets up Docker Buildx with QEMU support
- Performs a dry-run build of `src/Dockerfile`
- Validates multi-arch support (amd64, arm64, arm/v7)
- **Does NOT push** to registry — validation only

**Expected result**:
```
✓ Docker image built successfully (dry-run)
  Platforms: amd64, arm64, arm/v7
  Status: Build validation passed
```

---

## Stage 3: QEMU Boot Validation (qemu-boot-test.yml)

**Trigger**: Push to develop/yumi-stable, or PR, or manual trigger

**Workflow steps**:
1. Install QEMU and dependencies (arm, aarch64)
2. Load and validate `.env.build`
3. Check fork-locked URLs are pointing to `yumi-stable`
4. Verify module configuration exists
5. Generate pre-flight report

**Current status**: Pre-flight validation only
- Full QEMU boot test deferred to Phase 4
- Requires actual YumiOS image built from CustomPiOS

**To run locally**:
```bash
# Install dependencies
sudo apt-get install -y qemu-system-arm qemu-system-aarch64 qemu-utils

# Once an image is available, boot it:
./tests/test_qemu_boot_yumios.sh /path/to/image.img
```

---

## Stage 4: Full Image Build & Test (Manual, in CustomPiOS)

**How to build**:

```bash
# 1. Run CustomPiOS Docker builder
docker run -it \
  -v /path/to/YumiOS-Klipper-V2:/CustomPiOS \
  -v /tmp/yumios-builds:/output \
  yumi-lab/custompios:latest

# 2. Inside container, run build script
/CustomPiOS/nightly_build_scripts/custompios_nightly_build

# 3. Images will be in /output/yumios-*.zip
```

**Validation after build**:

```bash
# Boot image in QEMU
./tests/test_qemu_boot_yumios.sh /tmp/yumios-builds/yumios-klipper-v2-armv7.img

# Expected results:
# ✓ SSH connectivity verified
# ✓ System services checked
# ✓ Fork-locked configuration verified
```

---

## Fork-Locked Verification

To verify that all components are correctly pinned to `yumi-stable`:

**On running device** (via SSH):

```bash
# Check Klipper
cd /opt/klipper && git remote -v
# Expected: Yumi-Lab/klipper (yumi-stable)

# Check Moonraker
cd /opt/moonraker && git remote -v
# Expected: Yumi-Lab/moonraker (yumi-stable)

# Check branch
git branch -a
# Expected: on yumi-stable
```

**In configuration**:

```bash
# Check .env.build
grep "FORK_" src/.env.build
# Expected: All FORK_* variables point to yumi-Lab forks

# Check sync-upstream.yml
cat .github/workflows/sync-upstream.yml | grep "yumi-stable"
# Expected: Updates proposed to yumi-stable only
```

---

## Verification Checklist

- [x] Structure validation passes (modules exist, syntax valid)
- [x] Docker build succeeds (multi-arch dry-run)
- [x] Fork URLs are defined and pinned
- [x] QEMU boot test script available
- [ ] Full image builds without errors (Phase 4)
- [ ] QEMU boot succeeds (Phase 4)
- [ ] Klipper service starts (Phase 4)
- [ ] All fork URLs point to yumi-stable (Phase 4)

---

## Troubleshooting

### Bash syntax errors in workflow

```bash
# Run locally to debug
for script in $(find src/modules tests -name "*.sh" -type f); do
  bash -n "$script" || echo "Error in: $script"
done
```

### .env.build fails to load

```bash
# Debug environment loading
set -x
source src/.env.build
set +x

# Check for shell-specific syntax
grep -E "\[|{|}" src/.env.build | head -20
```

### Docker build fails

```bash
# Test locally with same Dockerfile
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --file src/Dockerfile \
  --load \
  src/
```

### QEMU boot issues

```bash
# Ensure QEMU is installed
qemu-system-arm --version
qemu-system-aarch64 --version

# Check netcat for connectivity
nc -zv 127.0.0.1 2222  # SSH port

# Check for QEMU processes
ps aux | grep qemu
```

---

## Related Documentation

- [MODULES.md](../MODULES.md) — Module structure and forks
- [WORKFLOWS.md](./WORKFLOWS.md) — CI/CD workflows overview
- [README.md](../README.md) — Project overview

