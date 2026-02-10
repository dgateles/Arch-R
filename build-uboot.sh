#!/bin/bash

#==============================================================================
# Arch R - Build U-Boot for R36S
#==============================================================================
# Builds U-Boot bootloader for RK3326 (R36S/RG351MP compatible)
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; exit 1; }

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

UBOOT_DIR="$SCRIPT_DIR/bootloader"
UBOOT_REPO="https://github.com/christianhaitian/RG351MP-u-boot"
UBOOT_SRC="$UBOOT_DIR/u-boot-rk3326"
OUTPUT_DIR="$SCRIPT_DIR/output/bootloader"

log "=== Arch R - Build U-Boot ==="

#------------------------------------------------------------------------------
# Step 1: Clone U-Boot
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking U-Boot source..."

mkdir -p "$UBOOT_DIR"

if [ ! -d "$UBOOT_SRC" ]; then
    log "  Cloning U-Boot for RK3326..."
    git clone --depth 1 "$UBOOT_REPO" "$UBOOT_SRC"
    log "  ✓ U-Boot cloned"
else
    log "  ✓ U-Boot source exists"
fi

cd "$UBOOT_SRC"

#------------------------------------------------------------------------------
# Step 2: Build U-Boot
#------------------------------------------------------------------------------
log ""
log "Step 2: Building U-Boot..."

# Set up cross-compiler (use Linaro if available, otherwise system)
if [ -d "/opt/toolchains/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu" ]; then
    export PATH=/opt/toolchains/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu/bin:$PATH
fi

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Build for OdroidGoA (compatible with R36S/RG351MP)
./make.sh odroidgoa 2>&1 | tail -20 || true

log "  ✓ U-Boot built"

#------------------------------------------------------------------------------
# Step 3: Copy artifacts
#------------------------------------------------------------------------------
log ""
log "Step 3: Copying bootloader files..."

mkdir -p "$OUTPUT_DIR"

# Copy the bootloader images
if [ -d "sd_fuse" ]; then
    cp sd_fuse/idbloader.img "$OUTPUT_DIR/"
    cp sd_fuse/uboot.img "$OUTPUT_DIR/"
    cp sd_fuse/trust.img "$OUTPUT_DIR/"
    log "  ✓ Bootloader files copied"
else
    error "sd_fuse directory not found - U-Boot build may have failed"
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== U-Boot Build Complete ==="
log ""
log "Bootloader files:"
ls -la "$OUTPUT_DIR/"
log ""
log "These will be automatically installed by build-image.sh"
log ""
log "✓ U-Boot ready for R36S!"
