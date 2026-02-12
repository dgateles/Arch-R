# Arch R

> Arch Linux-based Gaming Distribution for R36S Handheld

## About

Arch R is a custom Linux distribution optimized for the R36S handheld gaming console and all its clones.
Based on Arch Linux ARM with Kernel 6.6.89 (Rockchip BSP), Mesa Panfrost GPU, RetroArch, and EmulationStation.

For detailed progress tracking and release timeline, see the **[ROADMAP](ROADMAP.md)**.

## Building

### Prerequisites

- Ubuntu 22.04+ or WSL2
- Cross-compilation toolchain for aarch64
- 10GB+ free disk space

### Quick Start

```bash
# Setup build environment (run once)
./setup-toolchain.sh

# Build everything
./build-all.sh

# Output will be in output/ directory
```

## Project Structure

```
arch-r/
├── bootloader/     # U-Boot configuration
├── kernel/         # Kernel source and DTB
├── rootfs/         # Root filesystem overlay  
├── config/         # Configuration files
├── scripts/        # Runtime scripts
└── output/         # Build artifacts
```

## Hardware Support

- **SoC**: Rockchip RK3326
- **Display**: 640x480
- **USB OTG**: Host mode with VBUS power
- **Wi-Fi**: AIC8800 USB adapter support
- **Controls**: Full joypad + analog sticks

## License

GPL v3
