# GitHub Actions Workflows

This document describes the CI/CD workflows that validate and maintain YumiOS-Klipper-V2's fork-locked architecture.

## Overview

| Workflow | File | Triggers | Purpose |
|----------|------|----------|---------|
| **Sync Upstream** | `sync-upstream.yml` | Schedule (Mon 08:00 UTC) + manual | Detect CustomPiOS upstream updates → propose PR |
| **Build Validation** | `build.yml` | Push (develop, yumi-stable, protocol/*) + PR | Structure + syntax validation |
| **Tests** | `tests.yaml` | Push to any branch + tags | Run shell script test suite |
| **Docker Build** | `docker-build.yml` | Push (master, devel, release/v1, beta) + tags | Build Docker images → push to GHCR |
| **CustomPiOS Build** | `custompios-build.yml` | Manual (`workflow_dispatch`) + tag push | Build YumiOS images (armv7, aarch64) |

---

## Sync Upstream Workflow

### File
`.github/workflows/sync-upstream.yml`

### Trigger
- **Schedule**: Every Monday at 08:00 UTC
- **Manual**: Can be triggered via GitHub Actions UI (`workflow_dispatch`)

### What It Does
1. Fetches `guysoft/CustomPiOS#develop` (the upstream repo)
2. Compares develop/master branch with upstream
3. If new commits detected:
   - Creates a new PR to `yumi-stable` (or updates existing PR)
   - PR title: `[sync-upstream] CustomPiOS updates — MANUAL REVIEW REQUIRED`
   - PR is marked as **draft** (requires manual review before merge)
4. If no changes: Silent pass (no PR created)

### PR Workflow
```
CustomPiOS upstream → sync-upstream.yml → PR to yumi-stable
                                               ↓
                                         Manual review
                                               ↓
                                         Merge (if OK)
                                               ↓
                                         master auto-syncs
```

### Manual Trigger
Via GitHub Actions UI:
1. Go to **Actions** → **Sync Upstream CustomPiOS**
2. Click **Run workflow** → **Run workflow**

### Status Checks
✓ Branch exists (develop or master)
✓ Remote origin accessible
✓ GitHub token has permissions

---

## Build Validation Workflow

### File
`.github/workflows/build.yml`

### Trigger
- **Push**: `develop`, `yumi-stable`, `protocol/**` branches
- **Pull Request**: Against `develop` or `yumi-stable`

### What It Does
Runs 2 jobs (in parallel):

#### Job 1: structure-check
- ✓ Verify `src/modules` directory exists
- ✓ Count modules (must be ≥1)
- ✓ Check `src/.env.build` for format/variables
- ✓ Warn on hardcoded IPs/paths (doesn't fail)
- ✓ Verify expected FORK_* variables exist
- ✓ Check for duplicate fork URLs
- ✓ Validate bash syntax on all .sh + start_chroot_script files

#### Job 2: env-validation
- ✓ Source `src/.env.build` in isolation
- ✓ Verify YUMIOS_VERSION, FORK_KLIPPER, etc. are set
- ✓ Count modules and new modules
- ✓ Print summary

### Exit Codes
- **0 (PASS)**: All checks passed → can merge PR
- **1 (FAIL)**: Structure/syntax error → fix before merge
- **warnings**: Logged but don't block (informational)

### Expected Logs
```
✓ Module directory structure valid
✓ Environment variables structure valid
✓ All shell scripts have valid syntax
✓ No duplicate fork URLs
```

### Common Failures

**❌ "src/modules directory not found"**
→ Ensure `src/modules/` dir exists with at least one subdirectory

**❌ "Syntax error in src/modules/klipper/start_chroot_script"**
→ Run locally: `bash -n src/modules/klipper/start_chroot_script`
→ Fix syntax error

**❌ ".env.build not found"**
→ Ensure `src/.env.build` exists in repo

---

## Tests Workflow

### File
`.github/workflows/tests.yaml`

### Trigger
- **Push**: Any branch + tags
- Runs: `make test` (executes all test_*.sh scripts in `tests/` dir)

### Current Tests
- `test_qemu_setup.sh` — Validates QEMU binary copy logic
- `test_config_local_board.sh` — Validates local board config loading

---

## Docker Build Workflow

### File
`.github/workflows/docker-build.yml`

### Trigger
- **Push**: `master`, `devel`, `release/v1`, `beta` + tags
- Builds multi-arch Docker image (linux/amd64, linux/arm64, linux/arm/v7)
- Pushes to `ghcr.io/<owner>/custompios`

### Status
- Requires Docker credentials (handled via `GITHUB_TOKEN`)
- **Phase 3** will integrate this with hardware validation

---

## CustomPiOS Build Workflow

### File
`.github/workflows/custompios-build.yml`

### Trigger
- **Manual**: Via GitHub Actions UI (`workflow_dispatch`)
  - Optional input: Select board (all, armv7, aarch64)
- **Automatic**: On tag push (e.g., `git tag v2.0.0 && git push --tags`)

### What It Does
Builds YumiOS images for multiple architectures using CustomPiOS Docker container.

#### Job 1: build-matrix-setup
- Prepares build matrix based on input (all boards or specific board)
- Outputs: `raspberrypiarmhf` (armv7), `raspberry4-64` (aarch64)

#### Job 2: build-yumios (matrix job)
For each board architecture:
- ✓ Load build environment (src/.env.build)
- ✓ Pull CustomPiOS Docker image from GHCR
- ✓ Build YumiOS image with CustomPiOS
- ✓ Generate output filename (yumios-klipper-v2-armv7, yumios-klipper-v2-aarch64)
- ✓ Upload .zip artifact to GitHub Actions
- ⚠️ **Phase 4A**: Placeholder build (actual Docker build in Phase 4B)

#### Job 3: generate-checksums
- Downloads all build artifacts
- Generates SHA256 checksums (ARTIFACTS.sha256)
- Uploads checksums for verification

#### Job 4: build-summary
- Displays final status and artifact locations
- Lists next steps (verification, QEMU testing, release publishing)

### Manual Trigger (Phase 4B)

**Via GitHub UI:**
```
1. Go to Actions → CustomPiOS Build
2. Click "Run workflow"
3. Select board (default: all)
4. Click "Run workflow"
```

**Via gh CLI:**
```bash
gh workflow run custompios-build.yml -f board=all
```

**Or specific architecture:**
```bash
gh workflow run custompios-build.yml -f board=armv7
gh workflow run custompios-build.yml -f board=aarch64
```

### Output & Artifacts

Build artifacts are uploaded to GitHub Actions workflow run:
- `yumios-klipper-v2-armv7.zip` — armv7 image (Raspberry Pi 3/4 32-bit)
- `yumios-klipper-v2-aarch64.zip` — aarch64 image (Raspberry Pi 4B+ 64-bit)
- `ARTIFACTS.sha256` — checksums for verification

**Download artifacts:**
```bash
# List recent runs
gh run list --workflow custompios-build.yml

# Download artifacts from latest run
gh run download -D /tmp/yumios
```

### Verification

**Verify checksums:**
```bash
cd /tmp/yumios/checksums
sha256sum -c ARTIFACTS.sha256
```

### Exit Codes
- **0 (SUCCESS)**: All images built, checksums generated → ready for Phase 4C
- **1 (FAILURE)**: Build error or missing dependencies → check logs
- **warnings**: Logged but don't block (informational)

### Expected Duration
- **Phase 4A (dry-run)**: < 5 min (validation only)
- **Phase 4B (full build)**: 30-45 min per architecture

### Common Issues

**❌ "CustomPiOS image not found"**
→ Ensure `ghcr.io/<owner>/custompios:latest` exists
→ Check docker-build.yml has pushed image to GHCR

**❌ "Build timeout (120 minutes)"**
→ Docker build took >2 hours — check logs for stuck processes
→ May indicate missing dependencies in CustomPiOS Dockerfile

**❌ "Out of disk space"**
→ Docker builds consume ~10GB per image
→ Ensure runner has sufficient disk (GitHub-hosted has ~14GB free)

---

## Runbook

### Check Workflow Status
Via GitHub UI:
1. Go to **Actions** tab
2. Click workflow name
3. View latest run status + logs

### Re-run a Failed Workflow
1. Click the failed run
2. **Re-run failed jobs** or **Re-run all jobs**

### Skip Build Validation
Not recommended, but can skip by committing with `[skip-ci]` in commit message:
```bash
git commit -m "docs: Update README [skip-ci]"
```

### Test Locally Before Push
```bash
# Test shell syntax
bash -n src/modules/*/start_chroot_script

# Load environment
source src/.env.build

# Run tests
make test
```

---

## Troubleshooting

| Issue | Diagnosis | Fix |
|-------|-----------|-----|
| Build validation fails on PR | Check logs in Actions tab | Read error, fix locally, re-push |
| sync-upstream PR not created | Check schedule (Mon 08:00 UTC) | Manually trigger via UI |
| Docker build fails | Check `docker-build.yml` logs | Usually image not found — check src/Dockerfile |
| env.build syntax error | Run `source src/.env.build` locally | Fix variable definitions |

---

## Future Enhancements

- [ ] **Phase 3**: Add full build validation (Docker build dry-run)
- [ ] **Phase 3**: Hardware boot test on QEMU
- [ ] Artifact publishing (built images available for download)
- [ ] Auto-merge sync PR if all checks pass (configurable per release cycle)

---

**Last updated**: 2026-05-07  
**Maintained by**: YumiOS-Klipper-V2 Phase Runner
