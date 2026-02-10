#!/bin/bash

#==============================================================================
# Arch R - Root Filesystem Build Script
#==============================================================================
# Creates a minimal Arch Linux ARM rootfs optimized for R36S gaming
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
CACHE_DIR="$SCRIPT_DIR/.cache"

# Arch Linux ARM rootfs
ALARM_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
ALARM_TARBALL="$CACHE_DIR/ArchLinuxARM-aarch64-latest.tar.gz"

log "=== Arch R Rootfs Build ==="

#------------------------------------------------------------------------------
# Root check
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (for chroot and permissions)"
fi

#------------------------------------------------------------------------------
# Step 1: Download Arch Linux ARM
#------------------------------------------------------------------------------
log ""
log "Step 1: Checking Arch Linux ARM tarball..."

mkdir -p "$CACHE_DIR"

if [ ! -f "$ALARM_TARBALL" ]; then
    log "  Downloading Arch Linux ARM..."
    wget -O "$ALARM_TARBALL" "$ALARM_URL"
else
    log "  ✓ Using cached tarball"
fi

#------------------------------------------------------------------------------
# Step 2: Extract Base System
#------------------------------------------------------------------------------
log ""
log "Step 2: Extracting base system..."

# Clean previous rootfs (unmount stale bind mounts first)
if [ -d "$ROOTFS_DIR" ]; then
    warn "Removing existing rootfs..."
    for mp in run sys proc dev/pts dev; do
        mountpoint -q "$ROOTFS_DIR/$mp" 2>/dev/null && umount -l "$ROOTFS_DIR/$mp" 2>/dev/null || true
    done
    rm -rf "$ROOTFS_DIR"
fi

mkdir -p "$ROOTFS_DIR"

log "  Extracting... (this may take a while)"
bsdtar -xpf "$ALARM_TARBALL" -C "$ROOTFS_DIR"

log "  ✓ Base system extracted"

#------------------------------------------------------------------------------
# Step 3: Setup for chroot
#------------------------------------------------------------------------------
log ""
log "Step 3: Setting up chroot environment..."

# Copy QEMU for ARM64 emulation
if [ -f "/usr/bin/qemu-aarch64-static" ]; then
    cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
    log "  ✓ QEMU static copied"
else
    warn "qemu-aarch64-static not found, chroot may not work"
    warn "Install with: sudo apt install qemu-user-static"
fi

# Bind mounts
mount --bind /dev "$ROOTFS_DIR/dev"
mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
mount --bind /proc "$ROOTFS_DIR/proc"
mount --bind /sys "$ROOTFS_DIR/sys"
mount --bind /run "$ROOTFS_DIR/run"

# DNS resolution
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

log "  ✓ Chroot environment ready"

# Disable pacman Landlock sandbox (fails inside QEMU chroot)
if ! grep -q 'DisableSandbox' "$ROOTFS_DIR/etc/pacman.conf"; then
    sed -i '/^\[options\]/a DisableSandbox' "$ROOTFS_DIR/etc/pacman.conf"
    log "  ✓ Pacman sandbox disabled (QEMU chroot compatibility)"
fi

#------------------------------------------------------------------------------
# Step 4: Configure System
#------------------------------------------------------------------------------
log ""
log "Step 4: Configuring system..."

# Create setup script to run inside chroot
cat > "$ROOTFS_DIR/tmp/setup.sh" << 'SETUP_EOF'
#!/bin/bash
set -e

echo "=== Inside chroot ==="

# Initialize pacman keyring
pacman-key --init
pacman-key --populate archlinuxarm

# Update system
pacman -Syu --noconfirm

# Install essential packages
pacman -S --noconfirm --needed \
    base \
    linux-firmware \
    networkmanager \
    wpa_supplicant \
    dhcpcd \
    sudo \
    nano \
    htop \
    wget \
    usb_modeswitch \
    dosfstools \
    parted

# Audio
pacman -S --noconfirm --needed \
    alsa-utils \
    alsa-plugins

# Bluetooth
pacman -S --noconfirm --needed \
    bluez \
    bluez-utils

# Graphics & GPU
pacman -S --noconfirm --needed \
    mesa \
    libdrm \
    sdl2 \
    sdl2_mixer \
    sdl2_image \
    sdl2_ttf

# Gaming stack dependencies
pacman -S --noconfirm --needed \
    retroarch \
    libretro-core-info \
    freeimage \
    freetype2 \
    libglvnd \
    curl \
    unzip \
    p7zip \
    evtest

# LibRetro cores (available in Arch Linux ARM aarch64 repos)
pacman -S --noconfirm --needed \
    libretro-snes9x \
    libretro-gambatte \
    libretro-mgba \
    libretro-genesis-plus-gx \
    libretro-pcsx-rearmed \
    libretro-flycast \
    libretro-beetle-pce-fast \
    libretro-scummvm \
    libretro-melonds \
    libretro-nestopia \
    libretro-picodrive \
    || echo "Some libretro packages may not be available, continuing..."

# Download pre-compiled cores for those not in pacman repos
# Source: christianhaitian/retroarch-cores (optimized for ARM devices)
echo "Downloading additional libretro cores..."
CORES_URL="https://raw.githubusercontent.com/christianhaitian/retroarch-cores/master/aarch64"
CORES_DIR="/usr/lib/libretro"
mkdir -p "$CORES_DIR"

for core in fceumm_libretro.so mupen64plus_next_libretro.so \
            fbneo_libretro.so mame2003_plus_libretro.so \
            stella_libretro.so mednafen_wswan_libretro.so \
            ppsspp_libretro.so desmume2015_libretro.so; do
    if [ ! -f "$CORES_DIR/$core" ]; then
        wget -q -O "$CORES_DIR/$core" "$CORES_URL/$core" 2>/dev/null \
            && echo "  Downloaded: $core" \
            || echo "  Failed to download: $core (can be installed later)"
    fi
done

# Enable services
systemctl enable NetworkManager

# Disable unnecessary services for faster boot
systemctl disable systemd-timesyncd 2>/dev/null || true
systemctl disable dhcpcd 2>/dev/null || true
systemctl disable remote-fs.target 2>/dev/null || true

# Create gaming user 'archr'
if ! id archr &>/dev/null; then
    useradd -m -G wheel,audio,video,input -s /bin/bash archr
    echo "archr:archr" | chpasswd
fi

# Allow wheel group passwordless sudo
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd

# Set hostname
echo "archr" > /etc/hostname

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Performance tuning
cat > /etc/sysctl.d/99-archr.conf << 'SYSCTL_EOF'
# Arch R Performance Tuning
vm.swappiness=10
vm.dirty_ratio=20
vm.dirty_background_ratio=5
kernel.sched_latency_ns=1000000
kernel.sched_min_granularity_ns=500000
SYSCTL_EOF

# Enable ZRAM swap
cat > /etc/systemd/system/zram-swap.service << 'ZRAM_EOF'
[Unit]
Description=ZRAM Swap
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe zram && echo lz4 > /sys/block/zram0/comp_algorithm && echo 256M > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon -p 100 /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 && echo 1 > /sys/block/zram0/reset'

[Install]
WantedBy=multi-user.target
ZRAM_EOF

systemctl enable zram-swap

# Create directories
mkdir -p /home/archr/.config/retroarch/cores
mkdir -p /home/archr/.config/retroarch/saves
mkdir -p /home/archr/.config/retroarch/states
mkdir -p /home/archr/.config/retroarch/screenshots
mkdir -p /roms
chown -R archr:archr /home/archr

# Add ROMS partition to fstab (firstboot creates the partition)
if ! grep -q '/roms' /etc/fstab; then
    echo '# ROMS partition (created by firstboot)'  >> /etc/fstab
    echo '/dev/mmcblk1p3  /roms  vfat  defaults,utf8,noatime,nofail  0  0' >> /etc/fstab
fi

# Firstboot service
cat > /etc/systemd/system/firstboot.service << 'FB_EOF'
[Unit]
Description=Arch R First Boot Setup
Before=emulationstation.service
ConditionPathExists=!/var/lib/archr/.first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/local/bin/first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FB_EOF

systemctl enable firstboot

# EmulationStation service (auto-start gaming frontend)
cat > /etc/systemd/system/emulationstation.service << 'ES_EOF'
[Unit]
Description=EmulationStation-fcamod Gaming Frontend
After=multi-user.target firstboot.service
Wants=firstboot.service

[Service]
Type=simple
User=archr
WorkingDirectory=/home/archr
ExecStart=/usr/bin/emulationstation/emulationstation.sh
Environment="SDL_VIDEO_EGL_DRIVER=libEGL.so"
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
ES_EOF

# Don't enable ES yet — build-emulationstation.sh enables it after building
# systemctl enable emulationstation

# Boot splash service (very early — shows splash on fb0 before anything else)
cat > /etc/systemd/system/splash.service << 'SPLASH_EOF'
[Unit]
Description=Arch R Boot Splash
DefaultDependencies=no
After=systemd-tmpfiles-setup-dev.service
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/splash-show.sh
RemainAfterExit=yes
StandardInput=null
StandardOutput=null
StandardError=null

[Install]
WantedBy=sysinit.target
SPLASH_EOF

systemctl enable splash

# Auto-login on tty1 (fallback if ES not installed)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AL_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin archr --noclear %I $TERM
AL_EOF

# Journald size limit (save memory)
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size.conf << 'JD_EOF'
[Journal]
SystemMaxUse=16M
RuntimeMaxUse=16M
JD_EOF

# Suppress login messages (silent boot)
touch /home/archr/.hushlogin
chown archr:archr /home/archr/.hushlogin

#------------------------------------------------------------------------------
# System Optimization
#------------------------------------------------------------------------------
echo "=== System Optimization ==="

# Note: tmpfs entries for /tmp and /var/log are set in build-image.sh's fstab
# (build-image.sh creates a fresh fstab that overrides what's in the rootfs)

# Disable services that are not needed on this device
# NOTE: bluetooth, wifi, rfkill are left enabled — user decides what to use
systemctl disable lvm2-monitor 2>/dev/null || true
systemctl mask lvm2-lvmpolld.service lvm2-lvmpolld.socket 2>/dev/null || true

# Reduce kernel messages on console
echo 'kernel.printk = 3 3 3 3' >> /etc/sysctl.d/99-archr.conf

# Faster TTY login (skip issue/motd)
echo "" > /etc/issue
echo "" > /etc/motd

# ALSA default config for RK3326 (rk817 codec)
cat > /etc/asound.conf << 'ALSA_EOF'
# Arch R ALSA configuration for RK3326 (rk817 codec)
pcm.!default {
    type hw
    card 0
    device 0
}
ctl.!default {
    type hw
    card 0
}
ALSA_EOF

# Set default audio levels
amixer -c 0 sset 'Playback Path' SPK 2>/dev/null || true
amixer -c 0 sset 'Master' 80% 2>/dev/null || true

# Disable coredumps (save space)
echo 'kernel.core_pattern=|/bin/false' >> /etc/sysctl.d/99-archr.conf
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/disable.conf << 'CORE_EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
CORE_EOF

# Network defaults (WiFi powersave off for lower latency)
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/archr.conf << 'NM_EOF'
[connection]
wifi.powersave=2
NM_EOF

# Clean package cache
pacman -Scc --noconfirm

echo "=== Chroot setup complete ==="
SETUP_EOF

chmod +x "$ROOTFS_DIR/tmp/setup.sh"

# Run setup inside chroot
log "  Running setup inside chroot..."
chroot "$ROOTFS_DIR" /tmp/setup.sh

log "  ✓ System configured"

#------------------------------------------------------------------------------
# Step 5: Install Arch R Scripts and Configs
#------------------------------------------------------------------------------
log ""
log "Step 5: Installing Arch R scripts and configs..."

# Performance scripts
install -m 755 "$SCRIPT_DIR/scripts/perfmax" "$ROOTFS_DIR/usr/local/bin/perfmax"
install -m 755 "$SCRIPT_DIR/scripts/perfnorm" "$ROOTFS_DIR/usr/local/bin/perfnorm"
log "  ✓ Performance scripts installed"

# Splash screen script
install -m 755 "$SCRIPT_DIR/scripts/splash-show.sh" "$ROOTFS_DIR/usr/local/bin/splash-show.sh"
log "  ✓ Splash script installed"

# First boot script
install -m 755 "$SCRIPT_DIR/scripts/first-boot.sh" "$ROOTFS_DIR/usr/local/bin/first-boot.sh"
log "  ✓ First boot script installed"

# RetroArch config
mkdir -p "$ROOTFS_DIR/etc/archr"
cp "$SCRIPT_DIR/config/retroarch.cfg" "$ROOTFS_DIR/etc/archr/retroarch.cfg"
log "  ✓ RetroArch config installed"

# EmulationStation config (if exists)
if [ -f "$SCRIPT_DIR/config/es_systems.cfg" ]; then
    mkdir -p "$ROOTFS_DIR/etc/emulationstation"
    cp "$SCRIPT_DIR/config/es_systems.cfg" "$ROOTFS_DIR/etc/emulationstation/"
    log "  ✓ EmulationStation config installed"
fi

#------------------------------------------------------------------------------
# Step 6: Install Kernel and Modules
#------------------------------------------------------------------------------
log ""
log "Step 6: Installing kernel and modules..."

KERNEL_BOOT="$OUTPUT_DIR/boot"
KERNEL_MODULES="$OUTPUT_DIR/modules/lib/modules"

if [ -f "$KERNEL_BOOT/Image" ]; then
    mkdir -p "$ROOTFS_DIR/boot"
    cp "$KERNEL_BOOT/Image" "$ROOTFS_DIR/boot/"
    log "  ✓ Kernel Image installed"

    # Copy R36S DTB
    for dtb in "$KERNEL_BOOT"/*.dtb; do
        [ -f "$dtb" ] && cp "$dtb" "$ROOTFS_DIR/boot/" && \
            log "  ✓ DTB installed: $(basename "$dtb")"
    done
else
    warn "Kernel Image not found. Run build-kernel.sh first!"
fi

if [ -d "$KERNEL_MODULES" ]; then
    cp -r "$KERNEL_MODULES"/* "$ROOTFS_DIR/lib/modules/"
    log "  ✓ Kernel modules installed"
else
    warn "Kernel modules not found. Run build-kernel.sh first!"
fi

#------------------------------------------------------------------------------
# Step 7: Cleanup
#------------------------------------------------------------------------------
log ""
log "Step 7: Cleaning up..."

# Remove setup script
rm -f "$ROOTFS_DIR/tmp/setup.sh"

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
log "=== Rootfs Build Complete ==="

ROOTFS_SIZE=$(du -sh "$ROOTFS_DIR" | cut -f1)
log ""
log "Rootfs location: $ROOTFS_DIR"
log "Rootfs size: $ROOTFS_SIZE"
log ""
log "✓ Arch R rootfs ready!"
