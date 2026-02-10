#!/bin/bash

#==============================================================================
# Arch R - SD Card Image Builder
#==============================================================================
# Creates a flashable SD card image for R36S
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
IMAGE_DIR="$OUTPUT_DIR/images"
IMAGE_NAME="ArchR-R36S-$(date +%Y%m%d).img"
IMAGE_FILE="$IMAGE_DIR/$IMAGE_NAME"

# Partition sizes (in MB)
BOOT_SIZE=128        # Boot partition (FAT32)
ROOTFS_SIZE=4096     # Root filesystem (ext4) - increased for full Arch
# ROMS partition will use remaining space on actual SD card

# Total image size
IMAGE_SIZE=$((BOOT_SIZE + ROOTFS_SIZE + 32))  # +32MB for partition table

log "=== Arch R Image Builder ==="

#------------------------------------------------------------------------------
# Root check
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
fi

#------------------------------------------------------------------------------
# Step 1: Verify Prerequisites
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking prerequisites..."

if [ ! -d "$ROOTFS_DIR" ]; then
    error "Rootfs not found at: $ROOTFS_DIR"
    error "Run build-rootfs.sh first!"
fi

if [ ! -f "$ROOTFS_DIR/boot/Image" ]; then
    warn "Kernel Image not found in rootfs. Make sure kernel is installed."
fi

# Check required tools
for tool in parted mkfs.vfat mkfs.ext4 losetup; do
    if ! command -v $tool &> /dev/null; then
        error "Required tool not found: $tool"
    fi
done

log "  ✓ Prerequisites OK"

#------------------------------------------------------------------------------
# Step 2: Create Image File
#------------------------------------------------------------------------------
log ""
log "Step 2: Creating image file..."

mkdir -p "$IMAGE_DIR"

# Remove old image if exists
[ -f "$IMAGE_FILE" ] && rm -f "$IMAGE_FILE"

# Create sparse image file
dd if=/dev/zero of="$IMAGE_FILE" bs=1M count=0 seek=$IMAGE_SIZE 2>/dev/null
log "  ✓ Created ${IMAGE_SIZE}MB image"

#------------------------------------------------------------------------------
# Step 2.5: Install U-Boot Bootloader
#------------------------------------------------------------------------------
log ""
log "Step 2.5: Installing U-Boot bootloader..."

# Search for U-Boot binaries in multiple locations
UBOOT_DIR=""
for dir in "$OUTPUT_DIR/bootloader" \
           "$SCRIPT_DIR/bootloader/u-boot-rk3326/sd_fuse" \
           "$SCRIPT_DIR/bootloader/sd_fuse"; do
    if [ -f "$dir/idbloader.img" ] && [ -f "$dir/uboot.img" ] && [ -f "$dir/trust.img" ]; then
        UBOOT_DIR="$dir"
        break
    fi
done

if [ -n "$UBOOT_DIR" ]; then
    dd if="$UBOOT_DIR/idbloader.img" of="$IMAGE_FILE" bs=512 seek=64 conv=sync,noerror,notrunc 2>/dev/null
    dd if="$UBOOT_DIR/uboot.img" of="$IMAGE_FILE" bs=512 seek=16384 conv=sync,noerror,notrunc 2>/dev/null
    dd if="$UBOOT_DIR/trust.img" of="$IMAGE_FILE" bs=512 seek=24576 conv=sync,noerror,notrunc 2>/dev/null
    log "  ✓ U-Boot installed from $UBOOT_DIR"
else
    warn "U-Boot files not found!"
    warn "Run build-uboot.sh first for bootable image!"
fi

#------------------------------------------------------------------------------
# Step 3: Create Partitions
#------------------------------------------------------------------------------
log ""
log "Step 3: Creating partitions..."

# Create partition table
parted -s "$IMAGE_FILE" mklabel msdos

# Calculate partition boundaries
BOOT_START=16  # Start at 16MB for U-Boot space
BOOT_END=$((BOOT_START + BOOT_SIZE))
ROOTFS_START=$BOOT_END
ROOTFS_END=$((ROOTFS_START + ROOTFS_SIZE))

# Create partitions
parted -s "$IMAGE_FILE" mkpart primary fat32 ${BOOT_START}MiB ${BOOT_END}MiB
parted -s "$IMAGE_FILE" mkpart primary ext4 ${ROOTFS_START}MiB ${ROOTFS_END}MiB
parted -s "$IMAGE_FILE" set 1 boot on

log "  ✓ Partitions created"

#------------------------------------------------------------------------------
# Step 4: Setup Loop Devices
#------------------------------------------------------------------------------
log ""
log "Step 4: Setting up loop devices..."

LOOP_DEV=$(losetup -fP --show "$IMAGE_FILE")
BOOT_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

# Wait for partitions to appear
sleep 1

log "  Loop device: $LOOP_DEV"
log "  Boot: $BOOT_PART"
log "  Root: $ROOT_PART"

#------------------------------------------------------------------------------
# Step 5: Format Partitions
#------------------------------------------------------------------------------
log ""
log "Step 5: Formatting partitions..."

mkfs.vfat -F 32 -n BOOT "$BOOT_PART"
mkfs.ext4 -L ROOTFS -O ^metadata_csum "$ROOT_PART"

log "  ✓ Partitions formatted"

#------------------------------------------------------------------------------
# Step 6: Mount and Copy Files
#------------------------------------------------------------------------------
log ""
log "Step 6: Copying files..."

MOUNT_ROOT="$OUTPUT_DIR/mnt_root"
MOUNT_BOOT="$OUTPUT_DIR/mnt_boot"

mkdir -p "$MOUNT_ROOT" "$MOUNT_BOOT"
mount "$ROOT_PART" "$MOUNT_ROOT"
mount "$BOOT_PART" "$MOUNT_BOOT"

# Copy rootfs (excluding /boot)
log "  Copying rootfs..."
rsync -aHxS --exclude='/boot' "$ROOTFS_DIR/" "$MOUNT_ROOT/"

# Copy boot files
log "  Copying boot files..."
if [ -d "$ROOTFS_DIR/boot" ]; then
    cp "$ROOTFS_DIR/boot/Image" "$MOUNT_BOOT/"
    cp "$ROOTFS_DIR/boot/"*.dtb "$MOUNT_BOOT/" 2>/dev/null || true
fi

# Copy U-Boot DTB (required for U-Boot to work)
UBOOT_DTB="$SCRIPT_DIR/kernel/dts/R36S-DTB/R36S/Panel 0/rg351mp-kernel.dtb"
if [ -f "$UBOOT_DTB" ]; then
    cp "$UBOOT_DTB" "$MOUNT_BOOT/rg351mp-kernel.dtb"
    log "  ✓ U-Boot DTB installed (rg351mp-kernel.dtb)"
else
    warn "U-Boot DTB not found! U-Boot may not initialize."
fi

# Copy uInitrd if exists (optional — boot.ini has fallback)
if [ -f "$OUTPUT_DIR/boot/uInitrd" ]; then
    cp "$OUTPUT_DIR/boot/uInitrd" "$MOUNT_BOOT/"
    log "  ✓ uInitrd copied"
else
    log "  (No uInitrd — kernel will boot without initrd)"
fi

# Copy boot.ini from config/ (kernel 6.6 + systemd + PanCho)
if [ -f "$SCRIPT_DIR/config/boot.ini" ]; then
    cp "$SCRIPT_DIR/config/boot.ini" "$MOUNT_BOOT/boot.ini"
    log "  ✓ boot.ini installed (kernel 6.6 + PanCho)"
else
    error "boot.ini not found at config/boot.ini!"
fi

# PanCho panel selection system
PANCHO_SRC="$SCRIPT_DIR/../R36S-Multiboot/commonbootfiles/PanCho.ini"
if [ -f "$PANCHO_SRC" ]; then
    cp "$PANCHO_SRC" "$MOUNT_BOOT/PanCho.ini"
    log "  ✓ PanCho.ini installed (panel selection)"
else
    warn "PanCho.ini not found — panel selection will not work"
fi

# Panel DTBO overlays (ScreenFiles/)
PANELS_DIR="$OUTPUT_DIR/panels/ScreenFiles"
if [ -d "$PANELS_DIR" ]; then
    cp -r "$PANELS_DIR" "$MOUNT_BOOT/"
    panel_count=$(find "$MOUNT_BOOT/ScreenFiles" -name "*.dtbo" | wc -l)
    log "  ✓ Panel DTBOs installed (${panel_count} panels)"
else
    warn "Panel DTBOs not found! Run scripts/generate-panel-dtbos.sh first"
fi

# Boot splash images (convert PNG → raw BGRA 32bpp 640x480 for fb0)
log "  Converting splash images..."
SPLASH_SRC1="$SCRIPT_DIR/Arch-R.png"
SPLASH_SRC2="$SCRIPT_DIR/Arch-R-2.png"
SPLASH_CONVERTED=false

if command -v convert &>/dev/null; then
    if [ -f "$SPLASH_SRC1" ]; then
        convert "$SPLASH_SRC1" -resize 640x480! -depth 8 bgra:"$MOUNT_BOOT/splash-1.raw"
        log "  ✓ Splash image 1 converted ($(du -h "$MOUNT_BOOT/splash-1.raw" | cut -f1))"
        SPLASH_CONVERTED=true
    fi
    if [ -f "$SPLASH_SRC2" ]; then
        convert "$SPLASH_SRC2" -resize 640x480! -depth 8 bgra:"$MOUNT_BOOT/splash-2.raw"
        log "  ✓ Splash image 2 converted ($(du -h "$MOUNT_BOOT/splash-2.raw" | cut -f1))"
        SPLASH_CONVERTED=true
    fi
elif command -v ffmpeg &>/dev/null; then
    if [ -f "$SPLASH_SRC1" ]; then
        ffmpeg -y -loglevel error -i "$SPLASH_SRC1" -vf "scale=640:480" -pix_fmt bgra -f rawvideo "$MOUNT_BOOT/splash-1.raw"
        log "  ✓ Splash image 1 converted via ffmpeg"
        SPLASH_CONVERTED=true
    fi
    if [ -f "$SPLASH_SRC2" ]; then
        ffmpeg -y -loglevel error -i "$SPLASH_SRC2" -vf "scale=640:480" -pix_fmt bgra -f rawvideo "$MOUNT_BOOT/splash-2.raw"
        log "  ✓ Splash image 2 converted via ffmpeg"
        SPLASH_CONVERTED=true
    fi
else
    warn "Neither imagemagick nor ffmpeg found — splash images skipped"
    warn "Install with: sudo apt install imagemagick"
fi

if [ "$SPLASH_CONVERTED" = false ]; then
    warn "No splash images found (Arch-R.png / Arch-R-2.png)"
fi

# Create fstab (overrides rootfs fstab with correct entries)
cat > "$MOUNT_ROOT/etc/fstab" << 'FSTAB_EOF'
# Arch R fstab
# <device>        <dir>     <type>   <options>                              <dump> <pass>
LABEL=BOOT        /boot     vfat     defaults                               0      2
LABEL=ROOTFS      /         ext4     defaults,noatime                       0      1
# ROMS partition (created by firstboot service on first boot)
/dev/mmcblk1p3    /roms     vfat     defaults,utf8,noatime,nofail           0      0
# tmpfs — reduce SD card writes, improve performance
tmpfs             /tmp      tmpfs    defaults,nosuid,nodev,size=128M        0      0
tmpfs             /var/log  tmpfs    defaults,nosuid,nodev,noexec,size=16M  0      0
FSTAB_EOF
log "  ✓ Files copied"

#------------------------------------------------------------------------------
# Step 7: Cleanup
#------------------------------------------------------------------------------
log ""
log "Step 7: Cleaning up..."

sync
umount "$MOUNT_BOOT"
umount "$MOUNT_ROOT"
losetup -d "$LOOP_DEV"
rmdir "$MOUNT_ROOT" "$MOUNT_BOOT"

log "  ✓ Cleanup complete"

#------------------------------------------------------------------------------
# Step 8: Compress (optional)
#------------------------------------------------------------------------------
log ""
log "Step 8: Compressing image..."

if command -v xz &> /dev/null; then
    xz -9 -k "$IMAGE_FILE"
    COMPRESSED="${IMAGE_FILE}.xz"
    COMPRESSED_SIZE=$(du -h "$COMPRESSED" | cut -f1)
    log "  ✓ Compressed: $COMPRESSED ($COMPRESSED_SIZE)"
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
log ""
log "=== Image Build Complete ==="
log ""

IMAGE_SIZE_ACTUAL=$(du -h "$IMAGE_FILE" | cut -f1)
log "Image: $IMAGE_FILE"
log "Size: $IMAGE_SIZE_ACTUAL"
log ""
log "To flash to SD card:"
log "  sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress"
log ""
log "✓ Arch R image ready!"
