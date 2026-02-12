# Arch R — Roadmap to First Stable Release

> Tracking all milestones from project inception to v1.0 stable release.
> Updated daily as progress is made.

---

## Progress Timeline

### 2026-02-04 — Project Inception

- Initial commit with project structure
- Build scripts created: `build-kernel.sh`, `build-rootfs.sh`, `build-image.sh`, `build-all.sh`
- Cross-compilation environment configured (aarch64, Ubuntu host)
- Kernel 4.4.189 (christianhaitian/linux, branch `rg351`) — first attempt
  - Discovered systemd incompatible with kernel 4.4 (fails to detect /proc, /sys, /dev mount points)
  - Created custom `/init` script as workaround
  - Fixed dwc2.ko module installation (compiled but not installed by `modules_install`)
  - Created exFAT stub for kernel compilation
- Migrated to Kernel 6.6.89 (Rockchip BSP, `rockchip-linux/kernel` branch `develop-6.6`)
- Custom DTS created: `rk3326-gameconsole-r36s.dts` (base: `rk3326-odroid-go.dtsi`)
  - Joypad: `adc-joystick` + `gpio-mux` + `io-channel-mux`
  - Panel: `simple-panel-dsi` + `panel-init-sequence` (Panel 4 V22)
  - PMIC: power controller + full pinctrl (sleep/poweroff/reset)
  - USB OTG: `u2phy_otg` + `vcc_host` regulator
- Development documentation added

### 2026-02-10 — First Boot + Gaming Stack + Multi-Panel

**Kernel 6.6.89 boots successfully on R36S hardware:**
- Display Panel 4 V22 working (640x480 DSI)
- Systemd init OK with auto-login
- USB OTG (keyboard) working
- Boot via sysboot+extlinux

**Gaming stack deployed:**
- EmulationStation-fcamod v2.13.0.0 compiled natively (5.3MB binary)
- FreeImage 3.18.0 built from source (patches for GCC 15 + ARM NEON)
- RetroArch + 11 pacman cores + 8 pre-compiled cores
- Audio configured (ALSA rk817, SPK path, 80% volume)
- WiFi/Bluetooth ready (NetworkManager + bluez)

**Multi-panel DTBO system complete (18 panels):**
- 6 R36S originals + 12 clone panels (ST7703, NV3051D, JD9365DA)
- PanCho.ini panel selection integrated

**Runtime fixes integrated into build scripts:**
- Mali blob replaced with Mesa Panfrost (SDL3/sdl2-compat compatibility)
- ROMS partition auto-creation (firstboot service, 37 system directories)
- ES input configuration (gpio-keys + adc-joystick dual-device)
- SDL gamecontroller mappings
- Performance governors (perfmax/perfnorm, dArkOS-style)
- Battery LED monitoring service
- Boot splash (BGRA raw framebuffer, silent boot)
- ZRAM swap (256M lzo), tmpfs, journal limits

**Build system hardened:**
- 8 fallback ALARM mirrors
- Pacman Landlock disabled for QEMU chroot
- U-Boot fix (R36S-u-boot-builder working binary)
- Kernel Image staleness validation
- Root partition increased to 6GB

**First image generated:** `ArchR-R36S-20260210.img` (6.2GB raw / 1.3GB xz)

### 2026-02-11 — GPU Rendering Pipeline (Panfrost + gl4es)

**Panfrost GPU driver fully working:**
- Mali-G31 Bifrost bound to Panfrost driver
- OpenGL ES 3.1 available (card1 + renderD129)
- kmsro render-offload: card0 (rockchip-drm display) → card1 (panfrost GPU)
- 6 root causes found and fixed:
  1. Mali Midgard driver blocking Panfrost → disabled in kernel config
  2. DTS interrupt-names case mismatch (UPPERCASE → lowercase)
  3. Panfrost built-in crash → changed to loadable module
  4. Module version mismatch (`-dirty` suffix) → CONFIG_LOCALVERSION
  5. modules_install silent failure → `set -o pipefail`
  6. MESA_LOADER_DRIVER_OVERRIDE breaking kmsro → removed

**gl4es integration complete:**
- Cross-compiled gl4es for aarch64 with `GOA_CLONE=ON` (Cortex-A35, GBM, no X11)
- `libGL.so.1` (1.5MB) — Desktop GL → GLES 2.0 translation
- `libEGL.so.1` (67KB) — EGL wrapper (intercepts context creation)
- Rendering pipeline: ES (Desktop GL 2.1) → gl4es → GLES 2.0 → Panfrost (Mali-G31)
- Solved GLES 1.0 rejection by Mesa (EGL_BAD_ALLOC) — gl4es bypasses entirely

**EmulationStation switched to Desktop GL renderer:**
- Changed from `-DGLES=ON` (Renderer_GLES10.cpp) to `-DGL=ON` (Renderer_GL21.cpp)
- Reduced source patches from 6 to 3 (MAJOR/MINOR fix, null safety, GL context restore)
- Removed GLES1 header download + libGLESv1_CM build (no longer needed)
- KMSDRM + SDL3 rebuild preserved

**Scripts updated:**
- `emulationstation.sh` — gl4es env vars (LD_LIBRARY_PATH, LIBGL_*, SDL_VIDEO_EGL_DRIVER)
- `build-emulationstation.sh` — gl4es pre-install step, GL21 patches, `-DGL=ON`
- `rebuild-es-sdcard.sh` — complete rewrite for gl4es approach
- `strings` → `grep -ao` (binutils may not be installed after cleanup)

---

## What's Left for v1.0 Stable

### Critical (must work before release)

| Task | Status | Notes |
|------|--------|-------|
| ES rendering on screen | Not tested | gl4es + Panfrost pipeline needs hardware validation |
| Audio output | Not tested | rk817-codec configured in DTS but never tested on hardware |
| Game launch (RetroArch) | Not tested | ES → RetroArch → core → ROM pipeline |
| Button/joystick input in ES | Partially tested | es_input.cfg created, needs re-validation |
| Button/joystick input in games | Not tested | gamecontrollerdb.txt + RetroArch autoconfig |
| Clean shutdown/reboot | Not tested | PMIC pinctrl in DTS, needs kernel rebuild verification |

### High Priority (expected for release)

| Task | Status | Notes |
|------|--------|-------|
| Volume control (hotkeys) | Not tested | archr-hotkeys.py daemon |
| Brightness control | Not tested | MODE+VOL combo via hotkey daemon |
| Boot splash display | Not tested | BGRA raw → fb0 |
| Panel selection (PanCho) | Not tested | 18 DTBOs generated, boot.ini integration |
| Full build from scratch | Not tested | `build-all.sh` end-to-end |
| ROMS partition auto-create | Tested manually | firstboot service integrated |

### Medium Priority (can ship without, fix in updates)

| Task | Status | Notes |
|------|--------|-------|
| WiFi connection | Not tested | NetworkManager + AIC8800 driver |
| Bluetooth pairing | Not tested | bluez installed |
| Battery LED indicator | Installed | Python service, needs hardware test |
| Sleep/wake | Not implemented | PMIC sleep pinctrl in DTS |
| OTA updates | Not implemented | Future feature |
| Theme customization | Default only | ES-fcamod default theme |
| Headphone detection | Not tested | archr-hotkeys.py ALSA switch |

### Low Priority (post-release)

| Task | Status | Notes |
|------|--------|-------|
| Additional RetroArch cores | 19 installed | More can be added via pacman/AUR |
| Custom ES theme | Not started | Arch R branded theme |
| PortMaster integration | Not started | Native Linux game ports |
| DraStic (DS emulator) | Not started | Proprietary, needs license |
| Scraper integration | Not started | ES metadata scraping |
| Wi-Fi setup UI | Not started | In-ES WiFi configuration |

---

## Estimated Path to v1.0

**Current phase:** Hardware validation of GPU rendering pipeline

The next steps follow this sequence:

1. **Test gl4es + Panfrost rendering** — Flash updated SD card, verify ES displays on screen
2. **Fix audio** — Test rk817-codec, add DTS node if missing
3. **Validate game launch** — RetroArch core loading, input in games
4. **Full build test** — Run `build-all.sh` end-to-end on clean environment
5. **Polish** — Boot splash, hotkeys, shutdown, panel selection
6. **Release candidate** — Generate final image, test on multiple R36S units

---

*Last updated: 2026-02-11*
