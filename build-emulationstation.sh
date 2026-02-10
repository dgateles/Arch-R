#!/bin/bash

#==============================================================================
# Arch R - EmulationStation Build Script
#==============================================================================
# Builds EmulationStation-fcamod (christianhaitian fork) for aarch64
# inside the rootfs chroot environment.
#
# This runs AFTER build-rootfs.sh and BEFORE build-image.sh
# Requires: rootfs at output/rootfs with build deps installed
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
ROOTFS_DIR="$OUTPUT_DIR/rootfs"
CACHE_DIR="$SCRIPT_DIR/.cache"

# EmulationStation source
ES_REPO="https://github.com/christianhaitian/EmulationStation-fcamod.git"
ES_BRANCH="351v"
ES_CACHE="$CACHE_DIR/EmulationStation-fcamod"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log() { echo -e "${GREEN}[ES-BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[ES-BUILD] WARNING:${NC} $1"; }
error() { echo -e "${RED}[ES-BUILD] ERROR:${NC} $1"; exit 1; }

#------------------------------------------------------------------------------
# Checks
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (for chroot)"
fi

if [ ! -d "$ROOTFS_DIR/usr" ]; then
    error "Rootfs not found at $ROOTFS_DIR. Run build-rootfs.sh first!"
fi

log "=== Building EmulationStation-fcamod ==="
log "Branch: $ES_BRANCH"

#------------------------------------------------------------------------------
# Step 1: Clone / update EmulationStation source on host
#------------------------------------------------------------------------------
log ""
log "Step 1: Getting EmulationStation source..."

mkdir -p "$CACHE_DIR"

if [ -d "$ES_CACHE/.git" ]; then
    log "  Updating existing clone..."
    cd "$ES_CACHE"
    git fetch origin
    git checkout "$ES_BRANCH"
    git reset --hard "origin/$ES_BRANCH"
    cd "$SCRIPT_DIR"
else
    log "  Cloning EmulationStation-fcamod..."
    git clone --depth 1 -b "$ES_BRANCH" "$ES_REPO" "$ES_CACHE"
fi

log "  ✓ Source ready"

#------------------------------------------------------------------------------
# Step 2: Copy source into rootfs for native build
#------------------------------------------------------------------------------
log ""
log "Step 2: Setting up build environment in rootfs..."

BUILD_DIR="$ROOTFS_DIR/tmp/es-build"
rm -rf "$BUILD_DIR"
cp -a "$ES_CACHE" "$BUILD_DIR"

log "  ✓ Source copied to rootfs"

#------------------------------------------------------------------------------
# Step 3: Setup chroot
#------------------------------------------------------------------------------
log ""
log "Step 3: Setting up chroot..."

# Copy QEMU
if [ -f "/usr/bin/qemu-aarch64-static" ]; then
    cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
else
    error "qemu-aarch64-static not found. Install: sudo apt install qemu-user-static"
fi

# Bind mounts
mount --bind /dev "$ROOTFS_DIR/dev" 2>/dev/null || true
mount --bind /dev/pts "$ROOTFS_DIR/dev/pts" 2>/dev/null || true
mount --bind /proc "$ROOTFS_DIR/proc" 2>/dev/null || true
mount --bind /sys "$ROOTFS_DIR/sys" 2>/dev/null || true
mount --bind /run "$ROOTFS_DIR/run" 2>/dev/null || true
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

log "  ✓ Chroot ready"

#------------------------------------------------------------------------------
# Step 4: Build inside chroot
#------------------------------------------------------------------------------
log ""
log "Step 4: Building EmulationStation inside chroot..."

cat > "$ROOTFS_DIR/tmp/build-es.sh" << 'BUILD_EOF'
#!/bin/bash
set -e

echo "=== ES Build: Installing dependencies ==="

# Build dependencies
pacman -S --noconfirm --needed \
    base-devel \
    cmake \
    git \
    sdl2 \
    sdl2_mixer \
    freeimage \
    freetype2 \
    curl \
    rapidjson \
    boost \
    pugixml \
    alsa-lib \
    vlc \
    libdrm \
    mesa

# Mali GPU driver (provides EGL + GLES2 for RK3326/Mali-G31)
pacman -S --noconfirm --needed \
    mali-bifrost-g31-libgl-gbm \
    || echo "mali-bifrost-g31-libgl-gbm not available, will use mesa"

echo "=== ES Build: Compiling ==="

cd /tmp/es-build

# Clean previous build
rm -rf CMakeCache.txt CMakeFiles

# Configure — ES-fcamod auto-detects Mali/GLES
cmake . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-O2 -march=armv8-a+crc -mtune=cortex-a35"

# Build
make -j$(nproc)

echo "=== ES Build: Installing ==="

# Install binary
install -d /usr/bin/emulationstation
install -m 755 emulationstation /usr/bin/emulationstation/emulationstation

# Install resources
cp -r resources /usr/bin/emulationstation/

# Create symlink for easy execution
ln -sf /usr/bin/emulationstation/emulationstation /usr/local/bin/emulationstation

echo "=== ES Build: Complete ==="
ls -la /usr/bin/emulationstation/emulationstation
BUILD_EOF

chmod +x "$ROOTFS_DIR/tmp/build-es.sh"
chroot "$ROOTFS_DIR" /tmp/build-es.sh

log "  ✓ EmulationStation built and installed"

#------------------------------------------------------------------------------
# Step 5: Install Arch R configs
#------------------------------------------------------------------------------
log ""
log "Step 5: Installing Arch R EmulationStation configs..."

# es_systems.cfg
if [ -f "$SCRIPT_DIR/config/es_systems.cfg" ]; then
    mkdir -p "$ROOTFS_DIR/etc/emulationstation"
    cp "$SCRIPT_DIR/config/es_systems.cfg" "$ROOTFS_DIR/etc/emulationstation/"
    log "  ✓ es_systems.cfg installed"
fi

# ES launch script
install -m 755 "$SCRIPT_DIR/scripts/emulationstation.sh" \
    "$ROOTFS_DIR/usr/bin/emulationstation/emulationstation.sh"
log "  ✓ Launch script installed"

# Enable ES service
chroot "$ROOTFS_DIR" systemctl enable emulationstation 2>/dev/null || true
log "  ✓ EmulationStation service enabled"

#------------------------------------------------------------------------------
# Step 6: Cleanup
#------------------------------------------------------------------------------
log ""
log "Step 6: Cleaning up..."

# Remove build directory (saves ~200MB in rootfs)
rm -rf "$BUILD_DIR"
rm -f "$ROOTFS_DIR/tmp/build-es.sh"

# Remove build-only deps to save space
cat > "$ROOTFS_DIR/tmp/cleanup-es.sh" << 'CLEAN_EOF'
#!/bin/bash
# Remove build-only packages (keep runtime deps)
pacman -Rns --noconfirm cmake eigen 2>/dev/null || true
pacman -Scc --noconfirm
CLEAN_EOF
chmod +x "$ROOTFS_DIR/tmp/cleanup-es.sh"
chroot "$ROOTFS_DIR" /tmp/cleanup-es.sh
rm -f "$ROOTFS_DIR/tmp/cleanup-es.sh"

# Remove QEMU
rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"

# Unmount
umount -l "$ROOTFS_DIR/run" 2>/dev/null || true
umount -l "$ROOTFS_DIR/sys" 2>/dev/null || true
umount -l "$ROOTFS_DIR/proc" 2>/dev/null || true
umount -l "$ROOTFS_DIR/dev/pts" 2>/dev/null || true
umount -l "$ROOTFS_DIR/dev" 2>/dev/null || true

log "  ✓ Cleanup complete"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== EmulationStation Build Complete ==="
log ""
log "Installed:"
log "  /usr/bin/emulationstation/emulationstation  (binary)"
log "  /usr/bin/emulationstation/resources/         (themes/fonts)"
log "  /usr/bin/emulationstation/emulationstation.sh (launch script)"
log "  /usr/local/bin/emulationstation              (symlink)"
log "  /etc/emulationstation/es_systems.cfg         (system config)"
log ""
