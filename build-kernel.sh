#!/bin/bash

#==============================================================================
# Arch R - Kernel 6.6 Build Script for R36S
#==============================================================================
# Builds Linux kernel 6.6.89 (Rockchip BSP) with R36S DTS + systemd support
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"; exit 1; }

#------------------------------------------------------------------------------
# Configuration - Kernel 6.6 Rockchip BSP
#------------------------------------------------------------------------------

KERNEL_VERSION="6.6.89"
KERNEL_BRANCH="develop-6.6"
KERNEL_REPO="https://github.com/rockchip-linux/kernel.git"
DEFCONFIG="rockchip_linux_defconfig"
CONFIG_FRAGMENT="$SCRIPT_DIR/config/archr-6.6-r36s.config"

# DTS target
R36S_DTB="rk3326-gameconsole-r36s"

# Paths
KERNEL_SRC="${KERNEL_SRC:-/home/dgateles/Documentos/Projetos/kernel}"

# Output
OUTPUT_DIR="$SCRIPT_DIR/output"
BOOT_DIR="$OUTPUT_DIR/boot"
MODULES_DIR="$OUTPUT_DIR/modules"

# Cross-compilation
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

# Build parallelism
JOBS=$(nproc)

log "================================================================"
log "  Arch R - Kernel $KERNEL_VERSION (Rockchip BSP for R36S)"
log "================================================================"
log ""
log "Source:   $KERNEL_SRC"
log "Branch:   $KERNEL_BRANCH"
log "DTB:      $R36S_DTB"
log "Jobs:     $JOBS"

#------------------------------------------------------------------------------
# Step 1: Verify Kernel Source
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking kernel source..."

if [ ! -d "$KERNEL_SRC" ]; then
    log "  Cloning kernel 6.6 (rockchip-linux/kernel)..."
    log "  Branch: $KERNEL_BRANCH"
    git clone --depth 1 --branch "$KERNEL_BRANCH" \
        "$KERNEL_REPO" "$KERNEL_SRC"
    log "  Kernel cloned"
fi

if [ ! -f "$KERNEL_SRC/Makefile" ]; then
    error "Kernel source not found at: $KERNEL_SRC"
fi

ACTUAL_VERSION=$(make -C "$KERNEL_SRC" -s kernelversion 2>/dev/null)
log "  Kernel: $ACTUAL_VERSION"

#------------------------------------------------------------------------------
# Step 2: Configure Kernel
#------------------------------------------------------------------------------
log ""
log "Step 2: Configuring kernel..."

# Apply base defconfig
make -C "$KERNEL_SRC" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE $DEFCONFIG
log "  Base: $DEFCONFIG"

# Merge R36S-specific config fragment
if [ -f "$CONFIG_FRAGMENT" ]; then
    "$KERNEL_SRC/scripts/kconfig/merge_config.sh" \
        -m "$KERNEL_SRC/.config" "$CONFIG_FRAGMENT" 2>&1 | \
        grep -E "(^#|Value)" | head -20 || true
    make -C "$KERNEL_SRC" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE olddefconfig
    log "  Merged: $(basename "$CONFIG_FRAGMENT")"
else
    warn "Config fragment not found: $CONFIG_FRAGMENT"
fi

log "  Kernel configured"

#------------------------------------------------------------------------------
# Step 3: Build Kernel Image
#------------------------------------------------------------------------------
log ""
log "Step 3: Building kernel Image..."

make -C "$KERNEL_SRC" -j$JOBS ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE Image 2>&1 | \
    tail -5

if [ ! -f "$KERNEL_SRC/arch/arm64/boot/Image" ]; then
    error "Kernel Image build failed!"
fi

IMAGE_SIZE=$(du -h "$KERNEL_SRC/arch/arm64/boot/Image" | cut -f1)
log "  Kernel Image built ($IMAGE_SIZE)"

#------------------------------------------------------------------------------
# Step 4: Build Device Tree
#------------------------------------------------------------------------------
log ""
log "Step 4: Building Device Tree ($R36S_DTB)..."

make -C "$KERNEL_SRC" -j$JOBS ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE \
    "rockchip/${R36S_DTB}.dtb" 2>&1 | tail -5

if [ ! -f "$KERNEL_SRC/arch/arm64/boot/dts/rockchip/${R36S_DTB}.dtb" ]; then
    error "DTB build failed: ${R36S_DTB}.dtb"
fi

log "  DTB built: ${R36S_DTB}.dtb"

#------------------------------------------------------------------------------
# Step 5: Build Kernel Modules
#------------------------------------------------------------------------------
log ""
log "Step 5: Building kernel modules..."

make -C "$KERNEL_SRC" -j$JOBS ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE modules 2>&1 | \
    tail -5

log "  Kernel modules built"

#------------------------------------------------------------------------------
# Step 6: Install to Output Directory
#------------------------------------------------------------------------------
log ""
log "Step 6: Installing artifacts..."

mkdir -p "$BOOT_DIR"
mkdir -p "$MODULES_DIR"

# Copy kernel image
cp "$KERNEL_SRC/arch/arm64/boot/Image" "$BOOT_DIR/"
log "  Copied: Image"

# Copy R36S DTB
cp "$KERNEL_SRC/arch/arm64/boot/dts/rockchip/${R36S_DTB}.dtb" "$BOOT_DIR/"
log "  Copied: ${R36S_DTB}.dtb"

# Install modules
make -C "$KERNEL_SRC" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE \
    INSTALL_MOD_PATH="$MODULES_DIR" \
    modules_install 2>&1 | tail -5

# Remove symlinks (save space)
rm -f "$MODULES_DIR/lib/modules/"*/source 2>/dev/null || true
rm -f "$MODULES_DIR/lib/modules/"*/build 2>/dev/null || true

log "  Modules installed"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "================================================================"
log "  BUILD COMPLETE"
log "================================================================"
log ""

KERNEL_FULL=$(make -C "$KERNEL_SRC" -s kernelversion 2>/dev/null || echo "$KERNEL_VERSION")
IMAGE_SIZE=$(du -h "$BOOT_DIR/Image" | cut -f1)
DTB_SIZE=$(du -h "$BOOT_DIR/${R36S_DTB}.dtb" | cut -f1)
MODULES_SIZE=$(du -sh "$MODULES_DIR" 2>/dev/null | cut -f1 || echo "N/A")

log "Kernel: $KERNEL_FULL"
log ""
log "Artifacts:"
log "  Image:   $BOOT_DIR/Image ($IMAGE_SIZE)"
log "  DTB:     $BOOT_DIR/${R36S_DTB}.dtb ($DTB_SIZE)"
log "  Modules: $MODULES_DIR/ ($MODULES_SIZE)"
log ""
log "Kernel 6.6 ready for R36S!"
