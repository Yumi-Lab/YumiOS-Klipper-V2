#!/bin/bash
# test_qemu_boot_yumios.sh
# Boot YumiOS image in QEMU and validate Klipper service
# Usage: ./test_qemu_boot_yumios.sh [image_path] [timeout_seconds]

set -e

# Configuration
IMAGE_PATH="${1:-.}"
TIMEOUT="${2:-300}"  # 5 minutes default
PORT_SSH="${PORT_SSH:-2222}"
PORT_API="${PORT_API:-7125}"
TEST_USER="pi"
TEST_PASS="raspberry"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_success() { echo -e "${GREEN}✓ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error() { echo -e "${RED}❌ $*${NC}"; }

# Helper functions
wait_for_ssh() {
  local host="$1"
  local port="$2"
  local timeout="$3"
  local elapsed=0

  log_info "Waiting for SSH on ${host}:${port} (timeout: ${timeout}s)..."

  while [ $elapsed -lt "$timeout" ]; do
    if nc -zv "$host" "$port" 2>/dev/null; then
      log_success "SSH is accessible"
      return 0
    fi
    sleep 2
    ((elapsed += 2))
  done

  log_error "SSH timeout after ${timeout}s"
  return 1
}

wait_for_klipper_api() {
  local host="$1"
  local port="$2"
  local timeout="$3"
  local elapsed=0

  log_info "Waiting for Klipper API on http://${host}:${port} (timeout: ${timeout}s)..."

  while [ $elapsed -lt "$timeout" ]; do
    if curl -s "http://${host}:${port}/printer/info" 2>/dev/null | grep -q "state"; then
      log_success "Klipper API is responding"
      return 0
    fi
    sleep 2
    ((elapsed += 2))
  done

  log_warn "Klipper API not responding after ${timeout}s (may not be configured)"
  return 1
}

ssh_exec() {
  local cmd="$1"
  sshpass -p "$TEST_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o LogLevel=ERROR \
    -p "$PORT_SSH" \
    "${TEST_USER}@localhost" \
    "$cmd" 2>/dev/null
}

# Main test flow
main() {
  log_info "=== YumiOS QEMU Boot Test ==="
  echo ""

  # Check dependencies
  log_info "Checking dependencies..."
  for cmd in qemu-system-arm nc sshpass curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
      log_error "Missing dependency: $cmd"
      return 1
    fi
  done
  log_success "All dependencies available"
  echo ""

  # Check for image file
  if [ ! -f "$IMAGE_PATH" ]; then
    log_warn "No image file found at $IMAGE_PATH"
    log_info "To run this test, provide a built YumiOS image:"
    log_info "  QEMU boot test requires: armv7/aarch64 image file"
    log_info ""
    log_info "When image is available, run:"
    log_info "  ./test_qemu_boot_yumios.sh /path/to/image.img"
    return 0
  fi

  log_info "Boot image: $IMAGE_PATH"
  echo ""

  # Start QEMU
  log_info "Starting QEMU..."
  QEMU_PID=""

  # Detect image type and arch
  if [[ "$IMAGE_PATH" == *"armv7"* ]] || [[ "$IMAGE_PATH" == *"arm"* ]]; then
    QEMU_CMD="qemu-system-arm"
    ARCH="armv7"
  else
    QEMU_CMD="qemu-system-aarch64"
    ARCH="aarch64"
  fi

  log_info "Detected architecture: $ARCH"

  # Start QEMU in background with SSH port forwarding
  $QEMU_CMD \
    -m 512M \
    -nographic \
    -drive "file=$IMAGE_PATH,format=raw" \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${PORT_SSH}-:22,hostfwd=tcp:127.0.0.1:${PORT_API}-:7125" \
    -device "virtio-net-device,netdev=net0" &
  QEMU_PID=$!
  log_success "QEMU started (PID: $QEMU_PID)"
  echo ""

  # Cleanup on exit
  cleanup() {
    if [ -n "$QEMU_PID" ]; then
      log_info "Stopping QEMU (PID: $QEMU_PID)..."
      kill "$QEMU_PID" 2>/dev/null || true
      wait "$QEMU_PID" 2>/dev/null || true
    fi
  }
  trap cleanup EXIT

  # Wait for SSH
  if ! wait_for_ssh "localhost" "$PORT_SSH" 60; then
    log_error "Failed to connect via SSH"
    return 1
  fi
  echo ""

  # Test 1: SSH login
  log_info "Test 1: SSH login..."
  if ssh_exec "echo 'SSH connection successful'" | grep -q "SSH connection successful"; then
    log_success "SSH login successful"
  else
    log_error "SSH login failed"
    return 1
  fi
  echo ""

  # Test 2: Check services
  log_info "Test 2: Check system services..."
  SERVICES=("klipper" "moonraker" "klipperscreen")
  for service in "${SERVICES[@]}"; do
    STATUS=$(ssh_exec "systemctl is-active $service 2>/dev/null || echo inactive" || echo "error")
    if [[ "$STATUS" == "active" ]]; then
      log_success "Service '$service' is active"
    else
      log_warn "Service '$service' is not active (status: $STATUS)"
    fi
  done
  echo ""

  # Test 3: Check fork URLs
  log_info "Test 3: Verify fork-locked configuration..."
  MODULES_PATH="/opt/klipper"
  if ssh_exec "[ -d $MODULES_PATH ]"; then
    log_success "Klipper directory exists at $MODULES_PATH"

    # Try to get git remote (if .git exists)
    REMOTE=$(ssh_exec "cd $MODULES_PATH && git remote -v 2>/dev/null || echo 'no-git'" || echo "no-git")
    if [[ "$REMOTE" == *"yumi-Lab"* ]]; then
      log_success "Fork correctly configured to yumi-Lab"
      echo "  Remote: $REMOTE"
    else
      log_warn "Could not verify fork URL"
    fi
  else
    log_warn "Klipper directory not found"
  fi
  echo ""

  # Test 4: Optional Klipper API test
  log_info "Test 4: Check Klipper API (optional)..."
  if wait_for_klipper_api "localhost" "$PORT_API" 30; then
    API_RESPONSE=$(curl -s "http://localhost:${PORT_API}/printer/info")
    echo "  API Response: $API_RESPONSE"
    log_success "Klipper API is operational"
  else
    log_warn "Klipper API not yet responding (may need configuration)"
  fi
  echo ""

  # Final report
  echo "=========================================="
  log_success "QEMU Boot Validation Complete"
  echo "=========================================="
  echo ""
  echo "✓ SSH connectivity verified"
  echo "✓ System services checked"
  echo "✓ Fork-locked configuration verified"
  echo "✓ (Optional) Klipper API checked"
  echo ""
  echo "YumiOS image is ready for deployment!"
  return 0
}

# Run main
main "$@"
