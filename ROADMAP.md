# Arch R — Roadmap to First Stable Release

> Tracking all milestones from project inception to v1.0 stable release.
> Written as a development diary — updated daily as progress is made.

---

## Development Diary

### 2026-02-04 — Day 1: Project Inception & Architecture

Started the Arch R project — an Arch Linux ARM gaming distribution for the R36S handheld
(RK3326 SoC, Mali-G31 Bifrost GPU, 640x480 DSI display, dual analog sticks).

- Created project structure: `bootloader/`, `kernel/`, `config/`, `scripts/`, `output/`
- Wrote all build scripts from scratch:
  - `build-kernel.sh` — cross-compiles kernel for aarch64
  - `build-rootfs.sh` — creates Arch Linux ARM rootfs in chroot (QEMU)
  - `build-image.sh` — assembles SD card image with partitions
  - `build-all.sh` — orchestrates the full build chain
- Set up cross-compilation toolchain (aarch64-linux-gnu, Ubuntu host)

**First kernel attempt: 4.4.189** (christianhaitian/linux, branch `rg351`)
- Used Linaro GCC 6.3.1 toolchain
- U-Boot from `christianhaitian/RG351MP-u-boot`
- Built successfully but hit a wall: **systemd is incompatible with kernel 4.4**
  - `systemd[1]: Failed to determine whether /proc is a mount point: Invalid argument`
  - `systemd[1]: Failed to mount early API filesystems`
  - `systemd[1]: Freezing execution.`
- Created a custom `/init` script as workaround — got to shell prompt!
  - But no shutdown/reboot capability without systemd
- Discovered `dwc2.ko` (USB OTG) is compiled but NOT installed by `modules_install` —
  had to copy manually
- Created exFAT stub files (Kconfig/Makefile/exfat.c) because kernel build fails without them

**Decision: migrate to Kernel 6.6.89** (Rockchip BSP, `rockchip-linux/kernel`, branch `develop-6.6`)
- Systemd works properly with modern kernel
- Panfrost GPU driver available (open-source Mali-G31 support)
- Modern WiFi drivers (RTW88/89, MT76, iwlwifi)

**Custom DTS created: `rk3326-gameconsole-r36s.dts`**
- Base: `rk3326-odroid-go.dtsi` (Hardkernel OGA, same SoC)
- Joypad: `adc-joystick` + `gpio-mux` + `io-channel-mux` (mainline API, not the BSP odroidgo3-joypad)
- Panel: `simple-panel-dsi` with `panel-init-sequence` byte-arrays extracted from decompiled R36S DTBs
- PMIC: `rockchip,system-power-controller` with full pinctrl (sleep/poweroff/reset states)
- USB OTG: `u2phy_otg` enabled + `vcc_host` regulator (GPIO0 PB7 for VBUS power)
- SD aliases: `mmc0=sdio`, `mmc1=sdmmc` → boot SD card appears as mmcblk1

Added development documentation with technical context.

---

### 2026-02-06 — Day 3: Build Environment Finalized

First interactive Claude session. Refined build scripts, configured kernel config fragments,
researched WiFi driver modules for various USB adapters:

| Vendor | Chipsets | Module |
|--------|----------|--------|
| Realtek | RTL8188/8192/8723/8821/8822 | rtl8xxxu, rtw88, rtw89 |
| Intel | AX200/AX210 | iwlwifi |
| MediaTek | MT7601/7610/7612/7921 | mt76 |
| Atheros | AR9271/AR7010 | ath9k_htc |
| Ralink | RT2800/RT3070/RT5370 | rt2800usb |
| AIC | AIC8800 (R36S built-in) | aic8800 |

Kernel config updated with all WiFi modules enabled.
Rootfs build script finalized: Arch ARM base, ZRAM swap, gaming user `archr`.

---

### 2026-02-08 — Day 5: Kernel & Rootfs Iterations

Continued kernel and rootfs iterations. Multiple builds and tests.
Switched between kernel versions, testing build outputs:
- Kernel 6.6.89 BSP: Image (31MB), 16 DTB files, modules (69MB including WiFi)
- First SD card image generated (4.2GB) — ready for hardware testing

---

### 2026-02-09 — Day 6: Device Tree & Image Refinement

Two morning sessions focused on device tree and image integration.
Refined DTS for R36S hardware specifics:
- Panel 4 V22 timings (58MHz clock, 640x480)
- Boot parameters: `root=/dev/mmcblk1p2` (LABEL=ROOTFS fails without initrd)
- User `archr` / password `archr` (UID 1001, not 1000 — alarm user takes 1000)

---

### 2026-02-10 — Day 7: The Marathon (midnight to dawn)

**00:41 — Gaming Stack Planning**
Started planning the full gaming stack deployment. RetroArch, EmulationStation,
multi-panel support, performance scripts — everything needed to go from "boots to shell"
to "boots to game menu".

**01:00-01:46 — Massive Build Session**
Implemented everything in a single marathon push:

*EmulationStation-fcamod:*
- Cloned christianhaitian fork, branch `351v` (proven on RK3326 devices)
- Built natively inside rootfs chroot (QEMU aarch64) — 5.3MB binary
- Hit build issues:
  - FreeImage 3.18.0 not in ALARM repos → built from source with patches:
    - `override CXXFLAGS += -std=c++14` (bundled OpenEXR uses throw() specs removed in C++17)
    - `override CFLAGS += -include unistd.h` (bundled ZLib missing header)
    - `-DPNG_ARM_NEON_OPT=0` (undefined NEON symbols on aarch64)
  - ES cmake: `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` (old cmake_minimum_required)
  - ES missing cstdint: `-DCMAKE_CXX_FLAGS="-include cstdint"` (GCC 15 strictness)
  - pugixml submodule empty → `--recurse-submodules` on git clone
  - Pacman Landlock sandbox fails in QEMU chroot → `command pacman --disable-sandbox`
  - ALARM mirror 404s → added 8 fallback mirrors

*RetroArch + Cores:*
- 11 cores from pacman: snes9x, gambatte, mgba, genesis_plus_gx, pcsx_rearmed,
  flycast, beetle-pce-fast, scummvm, melonds, nestopia, picodrive
- 8 pre-compiled core slots: fceumm, mupen64plus_next, fbneo, mame2003_plus,
  stella, mednafen_wswan, ppsspp, desmume2015
- Core path: `/usr/lib/libretro/`

*Multi-Panel DTBO System (18 panels):*
- Wrote `scripts/generate-panel-dtbos.sh` — extracts panel-init-sequence from
  decompiled DTBs, generates DTSO overlays, compiles to DTBO
- 6 R36S originals: Panel 0-5 (NV3051D, ST7703, JD9365DA variants)
- 12 clone panels: R36H, R35S, R36 Max, RX6S, and variants
- PanCho.ini integrated: R1+button=originals, L1+button=clones, L1+Vol-=reset lock

*System Optimizations:*
- tmpfs: `/tmp` (128M), `/var/log` (16M)
- ZRAM: 256M lzo swap (not lz4 — CONFIG_CRYPTO_LZ4 not compiled!)
- Sysctl: swappiness=10, dirty_ratio=20, sched_latency=1ms
- ALSA: rk817 hw:0, SPK path, 80% volume
- perfmax/perfnorm: CPU + GPU + DMC governor scripts (dArkOS-style)
- Boot splash: BGRA raw → fb0, alternating images
- Silent boot: `console=tty3 fbcon=rotate:0 loglevel=0 quiet`

*First-boot service:*
- Creates ROMS partition (FAT32) from remaining SD card space
- Creates 37 system directories (snes/, gba/, psx/, etc.)
- Auto-disables after first run

**01:46 — Git commit: "Tons of tons"**
Committed the entire gaming stack, multi-panel system, and all optimizations.
This single commit represents ~6 hours of continuous development.

**02:00-03:20 — Hardware Testing & Hotfixes (5 rapid sessions)**

Flashed the image to SD card and booted the R36S for the first time with kernel 6.6.89.

**FIRST BOOT RESULT: SUCCESS!**
- Display Panel 4 V22 working (640x480 DSI)
- Systemd init OK, auto-login to archr user
- USB OTG keyboard working
- Boot via sysboot+extlinux

But immediately hit runtime issues:

| # | Issue | Root Cause | Fix |
|---|-------|-----------|-----|
| 1 | ZRAM swap FAILED | `modprobe zram: module not found` — kernel `-dirty` suffix mismatch | Auto-symlink in build-rootfs.sh |
| 2 | ES crash loop (exit 2) | XML malformed — missing root tag in es_settings.cfg | Added `<settings>` root element |
| 3 | ROMS partition timeout | firstboot didn't create partition, fstab waited 90s | `x-systemd.device-timeout=5s` |
| 4 | SDL3 + Mali SIGABRT | sdl2-compat dlopen(libSDL3) + Mali blob libgbm.so incompatible | Replaced Mali → Mesa Panfrost |
| 5 | ES "no systems found" | ROMS partition didn't exist + ES requires at least 1 ROM | Created partition + SystemInfo.sh |
| 6 | ES button config loop | No es_input.cfg → ES asks for config every boot | Pre-configured es_input.cfg |
| 7 | ES extremely slow | Governor permission denied (runs as user, needs root) | sudoers for perfmax/perfnorm |

Fixed each one live on the device, then integrated all fixes back into the build scripts.
Created `es_input.cfg` with dual-device mapping:
- gpio-keys (GUID `1900bb07...`) — 17 buttons (DPAD, ABXY, shoulders, START, SELECT, etc.)
- adc-joystick (GUID `19001152...`) — 4 axes (dual analog sticks)
- gamecontrollerdb.txt with SDL mappings for both devices

Also added: battery LED service, archr-release distro info, hotkey daemon (`archr-hotkeys.py`).

**U-Boot discovery:** The U-Boot from `R36S-u-boot` repo has `odroid_alert_leds()` with a
`while(1)` infinite loop in `init_kernel_dtb()`. Switched to `R36S-u-boot-builder` releases.

**First image generated:** `ArchR-R36S-20260210.img` (6.2GB raw / 1.3GB xz)

---

**11:18 — ES Display Debugging Begins**

EmulationStation was running (process alive, V2.13.0.0 logged) but **nothing appeared on screen**.
Started systematic debugging of the display pipeline.

**19:59-20:17 — The Five Root Causes (ES Display)**

Over two intensive evening sessions, found and fixed 5 separate root causes for ES display failure:

**Root Cause 1: ES SIGABRT crash (exit code 134)**
- Error: `basic_string: construction from null is not valid`
- Location: `Renderer_GLES10.cpp:129` — `glGetString(GL_EXTENSIONS)` returns NULL
- Why: Bug in `setupWindow()` at lines 95-96:
  ```
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 1);  // sets MAJOR=1
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 0);  // BUG! Overwrites to MAJOR=0
  ```
  Second line should be `CONTEXT_MINOR_VERSION`. With our GLES profile patch, this requests
  GLES 0.0 which doesn't exist → Mesa rejects → NULL context → NULL string → SIGABRT.
  dArkOS never sees this bug because Mali blob ignores GL version hints entirely.

**Root Cause 2: ALARM SDL3 Missing KMSDRM**
- `grep -ao kmsdrm /usr/lib/libSDL3.so*` → EMPTY
- ALARM builds SDL3 WITHOUT the KMSDRM video backend
- SDL falls back to offscreen/dummy → renders to memory, nothing on display
- Fix: Rebuild SDL3 from source with `-DSDL_KMSDRM=ON`

**Root Cause 3: Systemd Service vs VT Session**
- ES started by systemd service can't acquire DRM master (no VT session)
- SDL KMSDRM needs a real VT session with console access
- Failed approach: `emulationstation.service` with PAMName/TTYPath
- Working approach: getty@tty1 autologin → `.bash_profile` → `emulationstation.sh`
- Bonus bug: `After=multi-user.target` + `Before=getty@tty1` = circular dependency

**Root Cause 4: GL Context Lost After setIcon()**
- KMSDRM window created OK, GL extensions checked OK, then:
  `WARNING: Tried to enable vsync, but failed! (No OpenGL context has been made current)`
- In `Renderer.cpp::createWindow()`: `createContext()` → `setIcon()` → `setSwapInterval()`
- `setIcon()` calls `SDL_SetWindowIcon()` which through sdl2-compat/SDL3 deactivates the EGL context
- Fix: Add `SDL_GL_MakeCurrent()` at start of `setSwapInterval()`

**Root Cause 5: EGL API Not Bound to GLES**
- GL context created but shows `GL_RENDERER: llvmpipe` (software rendering!)
- SDL3's KMSDRM/EGL backend does NOT call `eglBindAPI(EGL_OPENGL_ES_API)` despite
  `SDL_GL_CONTEXT_PROFILE_ES` being set
- sdl2-compat enum remapping was checked — it's CORRECT (switch statement)
- `SDL_OPENGL_ES_DRIVER=1` env var does NOT fix it
- Fix: Call `eglBindAPI(EGL_OPENGL_ES_API)` directly before `SDL_GL_CreateContext`

Created `test-kmsdrm.py` diagnostic script (ctypes SDL2 + EGL) with 4 test cases to validate
each fix independently. Test 4 (GLES 2.0 + eglBindAPI) confirmed Panfrost hardware acceleration:
`GL_RENDERER: Mali-G31`, `GL_VERSION: OpenGL ES 3.1 Mesa`.

**But Test 3 (GLES 1.0 + eglBindAPI) failed with `EGL_BAD_ALLOC`** — Mesa Panfrost
and llvmpipe both reject GLES 1.0 context requests. ES-fcamod uses `Renderer_GLES10.cpp`
which requires GLES 1.0. This led to the gl4es solution the next day.

---

### 2026-02-11 — Day 8: Panfrost GPU & gl4es Integration

**17:42 — Panfrost GPU Deep Dive**

Started investigating why Panfrost GPU wasn't working despite having the driver in the kernel.
Discovered the GPU rendering pipeline was completely broken for multiple reasons.

**21:00-03:00 — The Six Root Causes (Panfrost GPU)**

Massive debugging session (107MB conversation transcript!) that traced through 6 separate
root causes preventing Panfrost from working:

**Root Cause 1: Mali Midgard Blocks Panfrost**
- BSP defconfig enables BOTH Mali proprietary driver AND Panfrost
- Mali Midgard binds to the GPU first → Panfrost can't bind → Mesa falls back to llvmpipe
- Fix: Disabled ALL Mali proprietary drivers in kernel config

**Root Cause 2: DTS interrupt-names Case Mismatch**
- Rockchip BSP DTS uses UPPERCASE: `interrupt-names = "GPU", "MMU", "JOB";`
- Panfrost driver uses `platform_get_irq_byname()` which is case-sensitive (strcmp)
- Panfrost looks for lowercase "gpu", "mmu", "job" → all return -ENODEV
- Fix: `&gpu { interrupt-names = "gpu", "mmu", "job"; };`

**Root Cause 3: Panfrost Built-in Crash**
- `CONFIG_DRM_PANFROST=y` (built-in) caused crash during early boot
- GPU initialization races with other subsystems when built-in
- Fix: Changed to module `CONFIG_DRM_PANFROST=m` for safe deferred loading

**Root Cause 4: Module Version Mismatch**
- Kernel reports version `6.6.89-dirty` (due to uncommitted DTS changes)
- Modules installed to `/lib/modules/6.6.89/` (no -dirty)
- `modprobe panfrost` fails: module directory doesn't match running kernel
- Fix: `CONFIG_LOCALVERSION="-archr"` + `CONFIG_LOCALVERSION_AUTO is not set`

**Root Cause 5: modules_install Silent Failure**
- `make modules_install | tail` — bash returns tail's exit code (0), not make's!
- modules_install was failing due to root-owned output directory from previous sudo builds
- Error was masked by `| tail` pipeline
- Fix: `set -o pipefail` in build scripts

**Root Cause 6: MESA_LOADER_DRIVER_OVERRIDE Breaks kmsro**
- Setting `MESA_LOADER_DRIVER_OVERRIDE=panfrost` forces Mesa to load panfrost for card0
- card0 is rockchip-drm (display controller only) → panfrost rejects it → llvmpipe fallback
- The correct flow: Mesa auto-detects card0 "rockchip" → loads kmsro → finds renderD129 (panfrost GPU)
- RK3326 has a split DRM architecture:
  - card0 = rockchip-drm (VOP/DSI/CRTC display) + renderD128
  - card1 = panfrost (Mali-G31 GPU) + renderD129
  - kmsro bridges display→GPU automatically
- Fix: Remove `MESA_LOADER_DRIVER_OVERRIDE` entirely

**Result: Panfrost fully working!** Mali-G31 bound, OpenGL ES 3.1 available, kmsro render-offload active.

**But:** GLES 1.0 still fails with `EGL_BAD_ALLOC` — Mesa Panfrost only supports GLES 2.0+.
ES-fcamod's `Renderer_GLES10.cpp` needs GLES 1.0.

**The gl4es Solution**

Key insight: Both `Renderer_GL21.cpp` (Desktop GL) and `Renderer_GLES10.cpp` (GLES 1.0)
use the **exact same fixed-function API** — `glVertexPointer`, `glMatrixMode`, `glLoadMatrixf`,
`glEnableClientState`, etc. The only difference is which library provides the symbols.

**gl4es** translates Desktop OpenGL → GLES 2.0. With gl4es:
- ES built with `-DGL=ON` → uses `Renderer_GL21.cpp` → links `libGL.so` (gl4es)
- gl4es translates GL calls → GLES 2.0 → Panfrost GPU
- gl4es EGL wrapper intercepts `eglCreateContext` → creates GLES 2.0 instead of Desktop GL
- Completely bypasses the GLES 1.0 problem

**Cross-compiled gl4es for aarch64:**
- Used `GOA_CLONE=ON` preset (targets RK3326 devices: RG351p/v, R36S)
  - Sets `-mcpu=cortex-a35 -march=armv8-a+crc+simd+crypto`
  - Enables: NOX11, EGL_WRAPPER, GLX_STUBS, GBM
- Output: `libGL.so.1` (1.5MB) + `libEGL.so.1` (67KB)
- Hit build issues:
  - `.cache/` owned by root from previous sudo → cloned to `/tmp/gl4es-build/`
  - cmake not installed → `pip3 install cmake`
  - pkg-config can't find libdrm/gbm/egl for cross-compile → created fake .pc files
  - Snap curl can't download to certain paths → used python3 urllib instead

**Updated all build scripts for gl4es:**
- `emulationstation.sh` — gl4es env vars:
  - `LD_LIBRARY_PATH=/usr/lib/gl4es` (load gl4es libraries)
  - `SDL_VIDEO_EGL_DRIVER=/usr/lib/gl4es/libEGL.so.1` (EGL wrapper)
  - `LIBGL_EGL=/usr/lib/libEGL.so.1` (tell gl4es where real Mesa EGL is — avoids self-loading loop)
  - `LIBGL_ES=2`, `LIBGL_GL=21`, `LIBGL_NPOT=1`
  - Removed `SDL_OPENGL_ES_DRIVER=1` (gl4es handles context type)
- `build-emulationstation.sh` — gl4es pre-install step, GL21 patches, `-DGL=ON`
- `rebuild-es-sdcard.sh` — complete rewrite for gl4es approach
- Reduced ES source patches from 6 (GLES10) to 3 (GL21):
  1. MAJOR/MINOR version fix
  2. Null safety for glGetString
  3. GL context restore in setSwapInterval

**Final rendering pipeline:**
```
ES (Desktop GL 2.1) → gl4es (translate) → GLES 2.0 → Panfrost (Mali-G31 GPU)
```

Created ROADMAP.md and linked from README.md.

---

## What's Left for v1.0 Stable

### Critical — Must Work Before Release

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | ES rendering on screen | Not tested | gl4es + Panfrost pipeline needs hardware validation |
| 2 | Audio output | Not tested | rk817-codec in DTS, never tested on hardware |
| 3 | Game launch (RetroArch) | Not tested | ES → RetroArch → core → ROM full pipeline |
| 4 | Button/joystick in ES | Partially tested | es_input.cfg created, needs re-validation |
| 5 | Button/joystick in games | Not tested | gamecontrollerdb.txt + RetroArch autoconfig |
| 6 | Clean shutdown/reboot | Not tested | PMIC pinctrl in DTS, needs verification |

### High Priority — Expected for Release

| # | Task | Status | Notes |
|---|------|--------|-------|
| 7 | Volume control (hotkeys) | Not tested | archr-hotkeys.py daemon |
| 8 | Brightness control | Not tested | MODE+VOL combo via hotkey daemon |
| 9 | Boot splash display | Not tested | BGRA raw → fb0 |
| 10 | Panel selection (PanCho) | Not tested | 18 DTBOs generated, boot.ini integration |
| 11 | Full build from scratch | Not tested | `build-all.sh` end-to-end |
| 12 | ROMS partition auto-create | Tested manually | firstboot service integrated |

### Medium Priority — Can Ship Without, Fix in Updates

| # | Task | Status | Notes |
|---|------|--------|-------|
| 13 | WiFi connection | Not tested | NetworkManager + AIC8800 driver |
| 14 | Bluetooth pairing | Not tested | bluez installed |
| 15 | Battery LED indicator | Installed | Python service, needs hardware test |
| 16 | Sleep/wake | Not implemented | PMIC sleep pinctrl in DTS |
| 17 | OTA updates | Not implemented | Future feature |
| 18 | Theme customization | Default only | ES-fcamod default theme |
| 19 | Headphone detection | Not tested | archr-hotkeys.py ALSA switch |

### Low Priority — Post-Release

| # | Task | Status | Notes |
|---|------|--------|-------|
| 20 | Additional RetroArch cores | 19 installed | More via pacman/AUR |
| 21 | Custom ES theme | Not started | Arch R branded theme |
| 22 | PortMaster integration | Not started | Native Linux game ports |
| 23 | DraStic (DS emulator) | Not started | Proprietary, needs license |
| 24 | Scraper integration | Not started | ES metadata scraping |
| 25 | Wi-Fi setup UI | Not started | In-ES WiFi configuration |

---

## Path to v1.0

**Current phase:** Hardware validation of GPU rendering pipeline

1. **Test gl4es + Panfrost rendering** — Flash updated SD card, verify ES displays on screen
2. **Fix audio** — Test rk817-codec, add DTS node if missing
3. **Validate game launch** — RetroArch core loading, input in games
4. **Full build test** — Run `build-all.sh` end-to-end on clean environment
5. **Polish** — Boot splash, hotkeys, shutdown, panel selection
6. **Release candidate** — Generate final image, test on multiple R36S units

---

*Last updated: 2026-02-11*
