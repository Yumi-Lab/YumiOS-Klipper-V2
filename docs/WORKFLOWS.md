# GitHub Actions Workflows

This document describes the CI/CD workflows that validate and maintain YumiOS-Klipper-V2's fork-locked architecture.

## Overview

| Workflow | File | Triggers | Purpose |
|----------|------|----------|---------|
| **Sync Upstream** | `sync-upstream.yml` | Schedule (Mon 08:00 UTC) + manual | Detect CustomPiOS upstream updates → propose PR |
| **Build Validation** | `build.yml` | Push (develop, yumi-stable, protocol/*) + PR | Structure + syntax validation |
| **Tests** | `tests.yaml` | Push to any branch + tags | Run shell script test suite |
| **Docker Build** | `docker-build.yml` | Push (master, devel, release/v1, beta) + tags | Build Docker images → push to GHCR |

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
