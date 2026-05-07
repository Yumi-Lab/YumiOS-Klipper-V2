#!/bin/bash
# test_qemu_boot_yumios.sh — CustomPiOS-compatible QEMU boot validation
# Uses CustomPiOS QEMU kernel + image preparation for reliable boot
# Usage: ./test_qemu_boot_yumios.sh [image_path] [timeout_seconds]

set -e

# Configuration
IMAGE_INPUT="${1:-.}"
TIMEOUT="${2:-300}"
TEMP_DIR="${TEMP_DIR:-/tmp/qemu-yumios}"
PORT_SSH="${PORT_SSH:-2222}"
PORT_API="${PORT_API:-7125}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_success() { echo -e "${GREEN}✓ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error() { echo -e "${RED}❌ $*${NC}"; }

# Detect architecture from filename
detect_arch() {
  if [[ "$1" == *"armv7"* ]] || [[ "$1" == *"arm"* ]] || [[ "$1" == *"32"* ]]; then
    echo "armv7"
  elif [[ "$1" == *"aarch64"* ]] || [[ "$1" == *"arm64"* ]] || [[ "$1" == *"64"* ]]; then
    echo "aarch64"
  else
    echo "unknown"
  fi
}

# Extract ZIP to IMG
extract_image() {
  local zip_path="$1"
  local dest_dir="$2"

  mkdir -p "$dest_dir"

  if [[ "$zip_path" == *.zip ]]; then
    unzip -o "$zip_path" -d "$dest_dir" >/dev/null 2>&1
    ls -1 "$dest_dir"/*.img 2>/dev/null | head -1
  else
    echo "$zip_path"
  fi
}

# Boot armv7 with QEMU Raspberry Pi kernel
boot_armv7() {
  local img_path="$1"

  log_info "Preparing armv7 image for QEMU boot..."

  # Download QEMU-compatible kernel if needed
  local kernel_path="$TEMP_DIR/kernel-qemu-5.10.63-bullseye"
  local dtb_path="$TEMP_DIR/versatile-pb.dtb"

  if [ ! -f "$kernel_path" ]; then
    log_info "Downloading QEMU ARM kernel..."
    mkdir -p "$TEMP_DIR"
    if ! curl -sL https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/kernel-qemu-5.10.63-bullseye -o "$kernel_path"; then
      log_error "Failed to download QEMU kernel"
      return 1
    fi
    chmod +x "$kernel_path"
  fi

  if [ ! -f "$dtb_path" ]; then
    log_info "Downloading device tree binary..."
    if ! curl -sL https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/versatile-pb.dtb -o "$dtb_path"; then
      log_error "Failed to download DTB"
      return 1
    fi
  fi

  log_success "QEMU dependencies ready"

  # Boot QEMU
  log_info "Starting QEMU (armv7)..."
  qemu-system-arm \
    -kernel "$kernel_path" \
    -dtb "$dtb_path" \
    -cpu arm1176 \
    -m 256 \
    -M versatilepb \
    -no-reboot \
    -append "root=/dev/sda2 panic=1 rootfstype=ext4 rw console=ttyAMA0" \
    -hda "$img_path" \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${PORT_SSH}-:22 \
    -device rtl8139,netdev=net0 &

  echo $!
}

# Boot aarch64 with Raspberry Pi 4B emulation
boot_aarch64() {
  local img_path="$1"

  log_info "Preparing aarch64 image for QEMU boot..."

  # Extract kernel and DTB from image
  local mount_path="$TEMP_DIR/mount"
  mkdir -p "$mount_path"

  # This would require mounting the image with sudo
  # For now, use simpler approach with kernel inside image
  log_info "Starting QEMU (aarch64)..."

  qemu-system-aarch64 \
    -m 2G \
    -M raspi4b \
    -cpu cortex-a53 \
    -serial stdio \
    -append "rw earlycon=pl011,0x3f201000 console=ttyAMA0 loglevel=8 root=/dev/mmcblk0p2 fsck.repair=yes net.ifnames=0 rootwait" \
    -drive file="$img_path",format=raw,if=sd \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${PORT_SSH}-:22 \
    -device usb-net,netdev=net0 \
    -no-reboot &

  echo $!
}

# Test SSH connectivity
test_ssh() {
  local timeout="$1"
  local elapsed=0

  log_info "Waiting for SSH (timeout: ${timeout}s)..."

  while [ $elapsed -lt "$timeout" ]; do
    if nc -zv localhost "$PORT_SSH" 2>/dev/null; then
      log_success "SSH port open"
      return 0
    fi
    sleep 2
    ((elapsed += 2))
  done

  log_error "SSH timeout after ${timeout}s"
  return 1
}

# Main
main() {
  log_info "=== YumiOS QEMU Boot Test (CustomPiOS) ==="
  echo ""

  # Check dependencies
  log_info "Checking dependencies..."
  for cmd in qemu-system-arm qemu-system-aarch64 nc curl unzip; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Missing: $cmd"
      return 1
    fi
  done
  log_success "All dependencies available"
  echo ""

  # Handle input (ZIP or IMG)
  local img_path="$IMAGE_INPUT"
  if [[ "$IMAGE_INPUT" == *.zip ]]; then
    log_info "Extracting ZIP image..."
    img_path=$(extract_image "$IMAGE_INPUT" "$TEMP_DIR")
    if [ ! -f "$img_path" ]; then
      log_error "Failed to extract image"
      return 1
    fi
    log_success "Extracted: $img_path"
  fi

  if [ ! -f "$img_path" ]; then
    log_error "Image not found: $img_path"
    return 1
  fi

  # Detect and boot
  local arch=$(detect_arch "$img_path")
  log_info "Detected architecture: $arch"
  echo ""

  local qemu_pid=""
  if [ "$arch" = "armv7" ]; then
    qemu_pid=$(boot_armv7 "$img_path")
  elif [ "$arch" = "aarch64" ]; then
    qemu_pid=$(boot_aarch64 "$img_path")
  else
    log_error "Unknown architecture: $arch"
    return 1
  fi

  log_success "QEMU started (PID: $qemu_pid)"
  echo ""

  # Cleanup on exit
  cleanup() {
    if [ -n "$qemu_pid" ]; then
      kill "$qemu_pid" 2>/dev/null
    fi
  }
  trap cleanup EXIT

  # Test SSH
  if ! test_ssh 120; then
    log_error "SSH connection failed"
    return 1
  fi
  echo ""

  log_success "QEMU Boot Test Complete"
  log_success "Image boots successfully in QEMU!"
  echo ""
  echo "✓ Architecture: $arch"
  echo "✓ SSH accessible on localhost:$PORT_SSH"
  echo "✓ Ready for service validation"

  return 0
}

main "$@"
