#!/bin/bash

#==============================================================================
# Arch R - Boot Splash Display
#==============================================================================
# Writes a pre-rendered splash image to /dev/fb0 during early boot.
# Images are BGRA 32bpp, 640x480 = 1228800 bytes each.
# Alternates between splash images on each boot.
#==============================================================================

FB="/dev/fb0"
SPLASH_DIR="/boot"

# Wait for framebuffer device (max 3 seconds)
for _ in $(seq 1 30); do
    [ -c "$FB" ] && break
    sleep 0.1
done
[ ! -c "$FB" ] && exit 0

# Hide text cursor on all VTs
echo 0 > /sys/class/graphics/fbcon/cursor_blink 2>/dev/null
for vt in /dev/tty{0..3}; do
    echo -ne "\033[?25l" > "$vt" 2>/dev/null
done

# Find available splash images
SPLASH_FILES=("$SPLASH_DIR"/splash-*.raw)
[ ! -f "${SPLASH_FILES[0]}" ] && exit 0

# Alternate images based on boot count
BOOT_COUNT_FILE="/var/lib/archr/boot_count"
if [ -f "$BOOT_COUNT_FILE" ]; then
    COUNT=$(cat "$BOOT_COUNT_FILE" 2>/dev/null || echo 0)
else
    mkdir -p "$(dirname "$BOOT_COUNT_FILE")"
    COUNT=0
fi
echo $((COUNT + 1)) > "$BOOT_COUNT_FILE" 2>/dev/null

IDX=$((COUNT % ${#SPLASH_FILES[@]}))
SPLASH="${SPLASH_FILES[$IDX]}"

# Write splash to framebuffer
dd if="$SPLASH" of="$FB" bs=4096 2>/dev/null

exit 0
