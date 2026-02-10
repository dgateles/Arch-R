#!/bin/bash

#==============================================================================
# Arch R - EmulationStation Launch Script
#==============================================================================
# Called by emulationstation.service (systemd)
# Sets up GPU/environment and launches EmulationStation-fcamod
#==============================================================================

export HOME=/home/archr
export SDL_ASSERT="always_ignore"
export TERM=linux
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export SDL_VIDEO_EGL_DRIVER=libEGL.so
export SDL_GAMECONTROLLERCONFIG_FILE="/etc/archr/gamecontrollerdb.txt"

# Ensure runtime dir exists
mkdir -p "$XDG_RUNTIME_DIR"

# Set performance governors for smooth UI
GPU_ADDR="ff400000"
if [ -f "/sys/devices/platform/${GPU_ADDR}.gpu/devfreq/${GPU_ADDR}.gpu/governor" ]; then
    echo performance > "/sys/devices/platform/${GPU_ADDR}.gpu/devfreq/${GPU_ADDR}.gpu/governor" 2>/dev/null || true
fi
if [ -f "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor" ]; then
    echo performance > "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor" 2>/dev/null || true
fi

# Create ES config directory if needed
mkdir -p "$HOME/.emulationstation"

# Link system configs if user doesn't have custom ones
if [ ! -f "$HOME/.emulationstation/es_systems.cfg" ] && [ -f /etc/emulationstation/es_systems.cfg ]; then
    ln -sf /etc/emulationstation/es_systems.cfg "$HOME/.emulationstation/es_systems.cfg"
fi

# Default ES settings for R36S (640x480)
if [ ! -f "$HOME/.emulationstation/es_settings.cfg" ]; then
    cat > "$HOME/.emulationstation/es_settings.cfg" << 'SETTINGS_EOF'
<?xml version="1.0"?>
<int name="MaxVRAM" value="150" />
<string name="LogLevel" value="disabled" />
<string name="ScreenSaverBehavior" value="black" />
<string name="TransitionStyle" value="instant" />
<string name="SaveGamelistsMode" value="on exit" />
SETTINGS_EOF
fi

# Launch EmulationStation
exec /usr/bin/emulationstation/emulationstation "$@"
