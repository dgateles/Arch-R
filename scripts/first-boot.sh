#!/bin/bash

#==============================================================================
# Arch R - First Boot Setup Script
#==============================================================================
# Runs on first boot to:
# 1. Create ROMS partition (FAT32) with remaining SD card space
# 2. Generate SSH keys and machine-id
# 3. Configure RetroArch and EmulationStation
# 4. Create ROM directories
#==============================================================================

FIRST_BOOT_FLAG="/var/lib/archr/.first-boot-done"

if [ -f "$FIRST_BOOT_FLAG" ]; then
    exit 0
fi

echo "=== Arch R First Boot Setup ==="

#------------------------------------------------------------------------------
# Detect SD card device
#------------------------------------------------------------------------------
ROOT_SOURCE=$(findmnt -no SOURCE /)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SOURCE" | head -1)
ROOT_DISK="/dev/${ROOT_DISK}"

echo "Root device: $ROOT_SOURCE"
echo "SD card: $ROOT_DISK"

#------------------------------------------------------------------------------
# Create ROMS partition (partition 3) if it doesn't exist
#------------------------------------------------------------------------------
ROMS_PART="${ROOT_DISK}p3"

if ! lsblk "$ROMS_PART" &>/dev/null; then
    echo "Creating ROMS partition..."
    echo ",,0c" | sfdisk --append "$ROOT_DISK" 2>/dev/null
    partprobe "$ROOT_DISK"
    sleep 2

    if lsblk "$ROMS_PART" &>/dev/null; then
        echo "  Formatting as FAT32..."
        mkfs.vfat -F 32 -n ROMS "$ROMS_PART"
        echo "  ROMS partition created!"
    else
        echo "  WARNING: Failed to create ROMS partition"
    fi
else
    echo "  ROMS partition already exists"
fi

#------------------------------------------------------------------------------
# Mount ROMS partition and create directories
#------------------------------------------------------------------------------
echo "Setting up ROM directories..."

mkdir -p /roms

if lsblk "$ROMS_PART" &>/dev/null; then
    mount "$ROMS_PART" /roms 2>/dev/null || true
fi

SYSTEMS=(
    "nes" "snes" "gb" "gbc" "gba" "nds"
    "megadrive" "mastersystem" "gamegear" "genesis" "segacd" "sega32x"
    "n64" "psx" "psp"
    "dreamcast" "saturn"
    "arcade" "mame" "fbneo" "neogeo"
    "atari2600" "atari7800" "atarilynx"
    "pcengine" "pcenginecd"
    "wonderswan" "wonderswancolor"
    "ngp" "ngpc"
    "virtualboy"
    "scummvm" "dos"
    "ports"
    "bios"
)

for sys in "${SYSTEMS[@]}"; do
    mkdir -p "/roms/$sys"
done

echo "  ROM directories created"

#------------------------------------------------------------------------------
# Generate SSH host keys
#------------------------------------------------------------------------------
echo "Generating SSH host keys..."
ssh-keygen -A 2>/dev/null || true

#------------------------------------------------------------------------------
# Set random machine-id
#------------------------------------------------------------------------------
echo "Generating machine ID..."
rm -f /etc/machine-id
systemd-machine-id-setup

#------------------------------------------------------------------------------
# Enable services
#------------------------------------------------------------------------------
echo "Enabling services..."
systemctl enable NetworkManager 2>/dev/null || true

#------------------------------------------------------------------------------
# Configure RetroArch
#------------------------------------------------------------------------------
echo "Configuring RetroArch..."

RA_DIR="/home/archr/.config/retroarch"
mkdir -p "$RA_DIR/cores"
mkdir -p "$RA_DIR/saves"
mkdir -p "$RA_DIR/states"
mkdir -p "$RA_DIR/screenshots"

if [ ! -f "$RA_DIR/retroarch.cfg" ] && [ -f /etc/archr/retroarch.cfg ]; then
    cp /etc/archr/retroarch.cfg "$RA_DIR/retroarch.cfg"
fi

# Set savefile/savestate directories to per-system on ROMS partition
sed -i "s|^savefile_directory =.*|savefile_directory = \"/roms/saves\"|" "$RA_DIR/retroarch.cfg" 2>/dev/null || true
sed -i "s|^savestate_directory =.*|savestate_directory = \"/roms/states\"|" "$RA_DIR/retroarch.cfg" 2>/dev/null || true
mkdir -p /roms/saves /roms/states

#------------------------------------------------------------------------------
# Configure EmulationStation
#------------------------------------------------------------------------------
echo "Configuring EmulationStation..."

ES_DIR="/home/archr/.emulationstation"
mkdir -p "$ES_DIR"

# Link system config
if [ ! -f "$ES_DIR/es_systems.cfg" ] && [ -f /etc/emulationstation/es_systems.cfg ]; then
    ln -sf /etc/emulationstation/es_systems.cfg "$ES_DIR/es_systems.cfg"
fi

chown -R archr:archr /home/archr

#------------------------------------------------------------------------------
# Mark first boot complete
#------------------------------------------------------------------------------
mkdir -p "$(dirname "$FIRST_BOOT_FLAG")"
touch "$FIRST_BOOT_FLAG"

echo "=== First Boot Setup Complete ==="
