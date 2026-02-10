#!/bin/bash

#==============================================================================
# Arch R - Generate uInitrd
#==============================================================================
# Creates a uInitrd (U-Boot initramfs) for R36S boot
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

OUTPUT_DIR="$SCRIPT_DIR/output"
ROOTFS_DIR="$OUTPUT_DIR/rootfs"
INITRD_DIR="$OUTPUT_DIR/initrd_work"
MODULES_DIR="$OUTPUT_DIR/modules/lib/modules"

# Find kernel version
KERNEL_VERSION=$(ls "$MODULES_DIR" 2>/dev/null | head -1)

log "=== Arch R - Generate uInitrd ==="
log "Kernel: $KERNEL_VERSION"

#------------------------------------------------------------------------------
# Check requirements
#------------------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
fi

if [ ! -d "$MODULES_DIR/$KERNEL_VERSION" ]; then
    error "Kernel modules not found. Run build-kernel.sh first."
fi

# Check for mkimage
if ! command -v mkimage &> /dev/null; then
    log "Installing u-boot-tools..."
    apt-get install -y u-boot-tools
fi

#------------------------------------------------------------------------------
# Create initramfs structure
#------------------------------------------------------------------------------
log ""
log "Step 1: Creating initramfs structure..."

rm -rf "$INITRD_DIR"
mkdir -p "$INITRD_DIR"/{bin,sbin,etc,proc,sys,dev,lib,lib64,usr/bin,usr/sbin,newroot}

# Copy busybox (static)
if [ -f /bin/busybox ]; then
    cp /bin/busybox "$INITRD_DIR/bin/"
else
    # Download static busybox for arm64
    log "  Downloading busybox..."
    wget -q -O "$INITRD_DIR/bin/busybox" \
        "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox" || \
    cp /usr/bin/busybox "$INITRD_DIR/bin/" 2>/dev/null || true
fi
chmod +x "$INITRD_DIR/bin/busybox"

# Create busybox symlinks
cd "$INITRD_DIR/bin"
for cmd in sh ash mount umount switch_root; do
    ln -sf busybox $cmd 2>/dev/null || true
done
cd "$SCRIPT_DIR"

log "  ✓ Busybox installed"

#------------------------------------------------------------------------------
# Copy kernel modules
#------------------------------------------------------------------------------
log ""
log "Step 2: Copying essential kernel modules..."

INITRD_MODULES="$INITRD_DIR/lib/modules/$KERNEL_VERSION"
mkdir -p "$INITRD_MODULES"

# Copy essential modules for boot
ESSENTIAL_MODULES=(
    "kernel/fs/ext4"
    "kernel/fs/fat"
    "kernel/fs/vfat"
    "kernel/drivers/mmc"
    "kernel/drivers/usb/storage"
)

for mod_path in "${ESSENTIAL_MODULES[@]}"; do
    SRC="$MODULES_DIR/$KERNEL_VERSION/$mod_path"
    if [ -d "$SRC" ]; then
        mkdir -p "$INITRD_MODULES/$(dirname $mod_path)"
        cp -r "$SRC" "$INITRD_MODULES/$(dirname $mod_path)/"
    fi
done

# Copy modules.* files
cp "$MODULES_DIR/$KERNEL_VERSION"/modules.* "$INITRD_MODULES/" 2>/dev/null || true

log "  ✓ Modules copied"

#------------------------------------------------------------------------------
# Create init script
#------------------------------------------------------------------------------
log ""
log "Step 3: Creating init script..."

cat > "$INITRD_DIR/init" << 'INIT_EOF'
#!/bin/sh

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Parse kernel command line
ROOT=""
for param in $(cat /proc/cmdline); do
    case $param in
        root=*)
            ROOT=${param#root=}
            ;;
    esac
done

# Wait for root device
echo "Waiting for root device: $ROOT"
sleep 2

# Handle LABEL=
if echo "$ROOT" | grep -q "LABEL="; then
    LABEL=${ROOT#LABEL=}
    for dev in /dev/mmcblk*p*; do
        if [ -b "$dev" ]; then
            # Try to find label (simple approach)
            ROOT=$dev
            break
        fi
    done
fi

# Mount root filesystem
echo "Mounting root: $ROOT"
mount -o rw "$ROOT" /newroot 2>/dev/null || mount -o rw /dev/mmcblk1p2 /newroot

# Check if mount succeeded
if [ ! -d /newroot/sbin ]; then
    echo "Failed to mount root filesystem!"
    echo "Dropping to shell..."
    exec /bin/sh
fi

# Switch to real root
echo "Switching to root filesystem..."
umount /proc /sys /dev 2>/dev/null
exec switch_root /newroot /sbin/init

# Fallback
echo "switch_root failed!"
exec /bin/sh
INIT_EOF

chmod +x "$INITRD_DIR/init"

log "  ✓ Init script created"

#------------------------------------------------------------------------------
# Create initramfs cpio
#------------------------------------------------------------------------------
log ""
log "Step 4: Creating initramfs..."

cd "$INITRD_DIR"
find . | cpio -H newc -o 2>/dev/null | gzip > "$OUTPUT_DIR/initramfs.cpio.gz"
cd "$SCRIPT_DIR"

log "  ✓ initramfs.cpio.gz created"

#------------------------------------------------------------------------------
# Create uInitrd (U-Boot format)
#------------------------------------------------------------------------------
log ""
log "Step 5: Creating uInitrd..."

mkimage -A arm64 -O linux -T ramdisk -C gzip \
    -d "$OUTPUT_DIR/initramfs.cpio.gz" \
    "$OUTPUT_DIR/boot/uInitrd"

log "  ✓ uInitrd created"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== uInitrd Generation Complete ==="

INITRD_SIZE=$(du -h "$OUTPUT_DIR/boot/uInitrd" | cut -f1)
log ""
log "Output: $OUTPUT_DIR/boot/uInitrd ($INITRD_SIZE)"
log ""
log "✓ uInitrd ready for R36S!"
