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

### 2026-02-12 — Day 9: Audio Breakthrough & Runtime Fixes

**Three-iteration audio debugging marathon** — each iteration revealed a deeper problem:

**Audio Iteration 1: Pinctrl Conflict**
- dmesg: `pin gpio2-19 already requested by 0-0020; cannot claim for rk817-codec`
- Root cause: Parent `&rk817` in odroid-go.dtsi already claims `i2s1_2ch_mclk` pin.
  Adding `pinctrl-0 = <&i2s1_2ch_mclk>` on the codec sub-device tries to claim the same pin again.
- Fix: Removed `pinctrl-names` and `pinctrl-0` from `&rk817_codec` override.

**Audio Iteration 2: DAI Mismatch**
- dmesg: `DMA mask not set` + `deferred probe pending` (no sound card created)
- Root cause: Adding `compatible = "rockchip,rk817-codec"` causes the MFD framework to assign
  the child's own `of_node` to the codec. The codec registers under `&rk817_codec`, but the
  sound card's `sound-dai = <&rk817>` still points to the parent → ASoC can't match the DAI.
- Fix: Override `rk817-sound` in DTS: `sound-dai = <&rk817_codec>` + add `#sound-dai-cells = <0>`.

**Audio Iteration 3: DAPM Routing (FINAL FIX)**
- dmesg: `ASoC: Failed to add route Mic Jack -> MICL(*)`
  `ASoC: Failed to add route HPOL(*) -> Headphones`
  `ASoC: Failed to add route SPKO(*) -> Speaker`
- Root cause: The BSP rk817 codec driver has **zero DAPM widgets** (no `SND_SOC_DAPM_*` macros,
  no `dapm_widgets` array, nothing). It uses a completely different mechanism:
  - `Playback Path` ALSA enum (OFF/SPK/HP/HP_NO_MIC/BT/SPK_HP/etc.)
  - `DAC Playback Volume` stereo control (0-255, inverted, -95dB to -1.1dB)
  - Direct register writes based on selected enum path
  The sound card's routing references widgets MICL/HPOL/HPOR/SPKO that don't exist → all 4 routes
  fail → card registration aborted → "No soundcards found".
- Fix: `/delete-property/ simple-audio-card,widgets` + `/delete-property/ simple-audio-card,routing`
  in the R36S DTS override.

**RESULT:** Sound card `rk817_int` successfully registered! `pcmC0D0p` (playback) and `pcmC0D0c`
(capture) created. Codec probed: `chip_name:0x81, chip_ver:0x75`. Only remaining warning:
`DAPM unknown pin Headphones` (from `hp-det-gpio`) — non-fatal.

**Other fixes this session:**

*unset_preload.so — LD_PRELOAD pollution solved:*
- Created `unset_preload.c` — tiny shared library with `__attribute__((constructor))` that calls
  `unsetenv("LD_PRELOAD")` after the dynamic linker has loaded all preloaded libraries.
- With `LD_PRELOAD="libGL.so.1 unset_preload.so"`: gl4es loads in ES process, but child processes
  (system(), popen()) don't inherit it. Without this, every subprocess (battery check, distro
  version, brightnessctl) loaded gl4es → init messages contaminated stdout.
- Confirmed working: debug log shows clean subprocess output (no `LIBGL:` messages).

*Battery DTS — 7 missing BSP properties added:*
- `monitor_sec=5`, `virtual_power=0`, `sleep_exit_current=300`, `power_off_thresd=3400`,
  `charge_stay_awake=0`, `fake_full_soc=100`, `nominal_voltage=3800`
- Silences BSP driver warnings. Battery monitoring confirmed: 84%, Discharging.

*ES Patch 5 — getShOutput() null safety:*
- `popen()` can return NULL if fork/exec fails (e.g., out of file descriptors)
- `fgets(buffer, size, NULL)` → SIGSEGV/SIGABRT (exit code 134)
- Added `if (!pipe) return "";` after popen() call

*Volume/brightness hotkey fixes (READY, NOT YET DEPLOYED):*
- Volume control: Changed from `Playback` (enum!) to `DAC Playback Volume` (actual level)
- Brightness: Added 5% minimum (prevents black screen), persistence to `~/.config/archr/brightness`
- current_volume script: Fixed to read `DAC Playback Volume` (was reading enum → always "N/A")
- MODE button: Fixed repeat handling (`val==2` no longer clears `mode_held`)

**Known issues (end of day):**
1. **Brightness:** `brightnessctl` changes sysfs values but screen doesn't visually change.
   PWM1 backlight device exists (max=1666) but PWM output may not reach the LCD backlight circuit.
2. **Volume buttons:** Fix ready in scripts, not yet deployed to SD card (needs sudo).
3. **ES crash on language change:** Occurs when saving es_settings.cfg. Needs investigation.
4. **Shutdown:** `systemctl poweroff` halts system but RK817 PMIC doesn't cut power — device stays on.
   `rockchip,system-power-controller` is set but full pinctrl causes kernel panic.

**Files changed (DTB deployed to BOOT, scripts need ROOTFS deploy):**
- `rk3326-gameconsole-r36s.dts` — audio routing fix, battery properties
- `scripts/emulationstation.sh` — audio init, brightness restore, unset_preload.so
- `scripts/archr-hotkeys.py` — DAC volume, brightness min/save, MODE repeat
- `scripts/current_volume` — reads DAC Playback Volume
- `scripts/unset_preload.c` — new file, LD_PRELOAD cleanup
- `build-gl4es.sh` — Step 6: cross-compiles unset_preload.so
- `build-emulationstation.sh` — unset_preload.so install + Patch 5
- `rebuild-es-sdcard.sh` — unset_preload.so install + Patch 5

---

### 2026-02-13 — Day 10: Audio, Shutdown, Brightness — All Working

Key achievements:
- **Audio fully working:** Speaker output confirmed, volume hotkeys (DAC), headphone jack detection
- **PMIC shutdown fixed:** systemd shutdown hook at `/usr/lib/systemd/system-shutdown/pmic-poweroff`
- **Brightness working:** Direct sysfs backlight (max=255), chmod 666 fix, MODE+VOL hotkeys
- **ES language crash fixed:** Patch 6 — `quitES(RESTART)` instead of in-place `delete/new GuiMenu`

---

### 2026-02-14 — Day 11: CPU 1512MHz Unlocked & Mesa 26 Built

Two major milestones today:

**CPU Frequency: 1200MHz → 1512MHz — UNLOCKED**

Previous approach (deleting all scaling properties from cpu0_opp_table) caused **black screen**
on every boot — tested 3 different variants, all failed. Deep analysis of `rockchip_opp_select.c`
and `rockchip_system_monitor.c` revealed two root causes:

1. Without pvtm properties, `volt_sel=-EINVAL` → wrong opp-microvolt variant selection
2. Without `rockchip,max-volt`, system monitor's low-temp voltage is unclamped
   (1350mV + 50mV = 1400mV > vdd_arm regulator max 1350mV)

**Breakthrough:** Decompiled dArkOS R36S-V20 DTB and discovered they use a completely
different approach — keep ALL scaling properties intact, just add `rockchip,avs = <1>`:

- Default `avs=0` = `AVS_DELETE_OPP` → the OPP deletion path is **always active**
- `avs=1` = `AVS_SCALING_RATE` → uses lenient `avs_scale(4)` check
- `opp_scale` for 1512MHz >> `avs_scale(4)` → exits early → **no OPPs disabled**

**ONE line DTS change**, no property deletions:
```dts
&cpu0_opp_table {
    rockchip,avs = <1>;
};
```

Confirmed working on hardware:
```
cpu cpu0: bin=2
cpu cpu0: pvtm-volt-sel=0       ← PVTM selects L0 correctly
cpu cpu0: avs=1                 ← AVS_SCALING_RATE active
CPU freq: 1512000 kHz           ← Full 1.5GHz!
CPU available: 408000 600000 816000 1008000 1200000 1248000 1296000 1416000 1512000
GPU freq: 520000000 Hz          ← 520MHz GPU also confirmed
```

**Mesa 26.0.0 — Built Successfully**

Created `build-mesa.sh` for native chroot build (QEMU aarch64). Key findings:
- Mesa 26 architecture change: single `libgallium-26.0.0.so` megadriver (no `/usr/lib/dri/`)
- GBM backend: `/usr/lib/gbm/dri_gbm.so`
- Panfrost now requires LLVM (CLC for compute shaders) — added llvm, clang, libclc, spirv deps
- Options removed in Mesa 26: `gallium-xa`, `gallium-vdpau`, `gallium-va`, `shared-glapi`
- `video-codecs=all_free` (underscore, not hyphen)
- Integrated into `build-all.sh` between rootfs and ES steps

**Mesa 26 needs on-device testing** — deploy libs to SD card, verify ES still renders.

**GPU target: 650MHz** — ARM specs for Mali-G31 list common operating frequencies of
650-800MHz. Currently at 520MHz (from rk3326.dtsi). Next session: investigate whether
RK3326 can drive Mali-G31 at 650MHz with appropriate vdd_logic voltage.

---

### 2026-02-15 — Day 12: GLES 1.0 Native, 78fps Stable, RetroArch Running

**The most transformative day of the project.** Three major breakthroughs:

**1. GLES 1.0 Native Rendering — gl4es ELIMINATED (+26% GPU performance)**

Discovered that Mesa's Panfrost driver CAN support GLES 1.0 via internal fixed-function
emulation (TNL — Transform and Lighting). The key was rebuilding Mesa 26 with the right flags:

```
meson setup build \
    -Dgles1=enabled \    # ← Enable GLES 1.0 state tracker (TNL)
    -Dglvnd=false \      # ← Direct Mesa EGL (no libglvnd dispatch)
    ...
```

**Before (gl4es pipeline):** ES (GL 2.1) → gl4es (translate) → GLES 2.0 → Panfrost = **46fps**
**After (native pipeline):** ES (GLES 1.0) → Mesa TNL → Panfrost = **57-58fps** (+26%!)

Build changes:
- ES rebuilt with `-DGLES=ON` (Renderer_GLES10.cpp) instead of `-DGL=ON` (Renderer_GL21.cpp)
- gl4es completely removed — no more `LD_PRELOAD`, `LIBGL_*` env vars, `unset_preload.so`
- emulationstation.sh simplified: just `MESA_NO_ERROR=1` + `SDL_VIDEODRIVER=KMSDRM`
- SDL3 rebuilt with `-DSDL_KMSDRM=ON` (ALARM's SDL3 still doesn't have KMSDRM)

**EGL_BAD_ALLOC Root Cause & Fix:**
After deploying Mesa 26 to SD card, ES crashed with `EGL_BAD_ALLOC`. Three nested issues:
1. Mesa was initially built with `glvnd=auto` → EGL dispatch through libglvnd, gallium
   megadriver missing GLES 1.0 state tracker
2. Rebuilt Mesa with `-Dgles1=enabled -Dglvnd=false` for direct Mesa EGL
3. **libglvnd version trap:** Old libglvnd's `libEGL.so.1.1.0` had HIGHER .so version than
   Mesa's `libEGL.so.1.0.0` → `ldconfig` preferred the old one! Had to manually remove
   old libglvnd files and fix symlinks.

**Mesa 26 direct libraries (no libglvnd):**
- `libEGL.so.1` → `libEGL.so.1.0.0` (360KB)
- `libGLESv1_CM.so.1` → `libGLESv1_CM.so.1.1.0` (78KB)
- `libGLESv2.so.2` → `libGLESv2.so.2.0.0` (93KB)
- `libgallium-26.0.0.so` (21MB) — with GLES 1.0 TNL state tracker

---

**2. FPS Stability: 57-58fps → 78fps STABLE (Root Cause: popen() fork overhead)**

After achieving GLES 1.0 native, FPS was 57-58 (should be 60+). Investigated multiple
hypotheses — depth buffer (patches 8-12), panel timing, governor settings — all rejected.

**The root cause was `popen("brightnessctl")` called 25 times per second!**

`BrightnessInfoComponent` polls every 40ms (`CHECKBRIGHTNESSDELAY=40`). When
`mExistBrightnessctl=true`, `getBrightnessLevel()` calls:
```cpp
popen("brightnessctl -m | awk -F',|%' '{print $4}'", "r")
```
Each `popen()` = `fork()` → on ARM Cortex-A35, fork() costs **2-5ms per call**.
25 forks/sec × 3ms average = **75ms/sec wasted** — pushes frames over 16.67ms budget.

**Patches 13-14 (the FPS fix):**
- Patch 13: `mExistBrightnessctl = false` → forces sysfs direct reads (already coded as
  fallback in `DisplayPanelControl.cpp` — open/read/close, microseconds)
- Patch 14: Polling intervals reduced: brightness 40→500ms, volume 40→200ms

**Result: 78fps rock-solid stable.**

**Panel Discovery: 78.2Hz refresh rate (NOT 60Hz!)**

RetroArch's DRM log revealed: `Mode 0: (640x480) 640 x 480, 78.209274 Hz`

The R36S panel actually runs at **78.2Hz**, not 60Hz. VSync IS engaging correctly —
ES and RetroArch both render at the panel's native rate. The "78fps instead of 60"
was not a vsync failure, but the panel being inherently faster than expected.

---

**3. GPU 600MHz Unlocked (zero overvolt)**

Extended GPU from 520MHz to **600MHz** at the same 1175mV — zero voltage increase:
- Stock rk3326.dtsi adds `opp-520000000` at 1175mV
- Fixed `vdd_logic` regulator max: 1150mV → 1175mV (was capping 520MHz OPP)
- Added 560MHz and 600MHz OPPs at same 1175mV
- **Chip bin=2** (from dmesg) — better quality silicon, room to push higher
- 520→600MHz = **+15.4% GPU performance** at zero voltage increase

**DRAM: 666MHz → 786MHz** enabled (`opp-786000000 { status = "okay" }` in dmc_opp_table)
— ~18% more memory bandwidth.

---

**4. RetroArch Built & Running (Video Works, Audio NOT Working)**

Built RetroArch v1.22.2 from source (`build-retroarch.sh`):
- `--enable-kms --enable-egl --enable-opengles --enable-opengles3`
- `--disable-x11 --disable-wayland --disable-qt --disable-vulkan`
- `--disable-pulse --disable-jack --enable-alsa --enable-udev`
- CFLAGS: `-O2 -march=armv8-a+crc -mtune=cortex-a35`
- Binary: 16MB, KMS/DRM context, GLES 3.1 via Panfrost

**Video:** Working perfectly — Mali-G31 MC1 (Panfrost), OpenGL ES 3.1 Mesa 26.0.0
**Input:** gpio-keys detected as joypad, autoconfig working (some launches)
**Audio:** ALSA initializes successfully but **NO sound output**
**Game launch:** Super Mario World (SNES) runs, video smooth, returns to ES cleanly

Investigated dArkOS RG351MP audio approach:
- `asound.conf`: `plug → dmix → hw:0,0` at 44100 Hz (we had bare `type hw`)
- `audio_device = ""` (empty, not "default")
- `audio_volume = "6.0"` (+6dB software boost)
- `verifyaudio.sh`: restores mixer state after each game exit

Applied all dArkOS-style audio config but still no sound. Suspected root cause:
RetroArch's microphone driver opens a capture ALSA connection (`[Microphone] Initialized
microphone driver.`). dArkOS builds with `--disable-microphone` — we don't.
**Next step: rebuild RetroArch with `--disable-microphone` and test.**

**Known Issues (end of day):**
- **RetroArch audio:** No sound despite ALSA init success. Needs `--disable-microphone` rebuild.
- **Volume on exit:** RetroArch modifies system volume on exit. Wrapper now saves/restores.
- **Kernel panic on shutdown:** "Attempted to kill the idle task!" — likely PMIC shutdown hook
  causing I2C operations while kernel is shutting down. Needs investigation.

**Performance patches applied to ES (quick-rebuild-es.sh):**
- Patches 1-7: Context fixes (go2, MINOR, ES profile, null safety, MakeCurrent, getShOutput, language)
- Patches 8-12: Depth buffer optimization (24→0, stencil, disable depth test)
- Patches 13-14: **THE FPS FIX** — popen elimination + polling interval reduction

---

### 2026-02-15 (cont.) — ES Audio Deep Investigation

**Extensive debugging of ES audio silence.** Three separate investigation rounds.

**Findings:**
- ALSA hardware pipeline works: `speaker-test` plays 440Hz tone through speaker and headphone
- Speaker amp GPIO 116 sysfs workaround confirmed working (direction=out, value=1)
- Volume buttons confirmed working in hotkey daemon log (VOL+/VOL- events handled correctly)
- AudioDevice corrected from "Speaker" to "DAC" in es_settings.cfg (VolumeControl needs correct mixer name)
- asound.conf simplified: `plug → hw:0,0` (removed dmix — dArkOS also removes it for games)
- SDL3 ALSA backend opens successfully: `SDL chose audio backend 'alsa'`, `PCM open 'default'`
- VolumeControl init succeeds: finds "DAC" mixer element, Mixer initialized

**Root Cause Found — ES-fcamod audio architecture has two independent features:**

1. **`playRandomMusic()` (startup)** — searches `~/.emulationstation/music/` for .ogg/.mp3 files.
   **This directory didn't exist!** → no files found → silent startup.
2. **`bgsound` (theme per-system)** — plays music from theme's `<sound name="bgsound">` element
   when user **scrolls between systems**. Not triggered on initial display.
3. **Theme epic-cody has ZERO navigation sounds** — no menuOpen, back, launch, scrollSound.

Without startup music AND without scrolling between systems, ES is **designed to be silent**.

**Fixes deployed:**
- Created `~/.emulationstation/music/` with 94 symlinks to theme .ogg files
- Updated emulationstation.sh: auto-detects active theme from es_settings.cfg (works with ANY theme)
- Added Patch 15 to quick-rebuild-es.sh: AudioManager diagnostic logging (themeChanged, playMusic, playRandomMusic)

**Also discovered:** AudioManager has ZERO success logging — `playMusic()` only logs on `Mix_LoadMUS` failure, `themeChanged()` has no LOG statements at all. Patch 15 adds diagnostic logging for next ES rebuild.

**REGRESSION:** Last test showed "sem beep, sem som" — even the speaker-test beep stopped working.

**Status: ES rebuild with Patch 15 (AudioManager logging) planned for next session.**

---

### 2026-02-17 — ROOT CAUSE FOUND: `use-ext-amplifier` (Audio FIXED!)

**The speaker audio root cause was a missing DTS property — not a software issue.**

After rebuilding ES with Patch 15 (AudioManager diagnostic logging), logs confirmed the entire
software chain was working perfectly: `playRandomMusic()` found 94 files, `playMusic()` loaded OGG,
`NOW PLAYING: snes`, SDL3 ALSA backend opened `default` at 48kHz. VolumeControl found DAC mixer.
speaker-test returned rc=0. **But zero sound from speaker.**

**Root cause analysis of `rk817_codec.c`:**

The BSP rk817 codec driver has THREE distinct SPK paths in `rk817_digital_mute_dac()` and
`rk817_set_playback_path()`, selected by DTS boolean properties:

1. `out-l2spk-r2hp` → Left→ClassD, Right→HP (costdown design)
2. `!use_ext_amplifier` → Internal Class-D ON, **DACL/DACR DOWN** (line outputs disabled)
3. `use_ext_amplifier` → Internal Class-D OFF, **DACL/DACR ON** (line outputs enabled)

The R36S hardware routes audio: DAC → line outputs (DACL/DACR) → external amp (GPIO 116) → speaker.
Without `use-ext-amplifier`, the codec wrote `ADAC_CFG1 = 0x03` (DACL_DOWN | DACR_DOWN), disabling
the line outputs entirely. The external amp received zero signal → zero sound.

**Why speaker-test rc=0 was misleading:** ALSA PCM write succeeds because DMA→I2S works fine.
The data reaches the codec's digital side. But the codec's ANALOG output stage (DACL/DACR) was
powered down at the register level (register 0x2f, bits 0-1). rc=0 does NOT mean sound came out.

**Fix:** Added `use-ext-amplifier;` to `&rk817_codec` DTS node. DTB-only rebuild (1 second).
Deployed new DTB to SD card BOOT partition.

**Result: AUDIO WORKING — both EmulationStation AND RetroArch!**

This was root cause #22 of the project. A single boolean DTS property controlled whether the
codec sent audio to the correct output pins.

---

### 2026-02-17 (cont.) — Boot Time Optimization: 35s → 29s

Started the session with a 35-second boot time. ArkOS clocks in at 21 seconds. Challenge accepted.

**Where does the time go?**

First, I needed real data. The `boot-timing.service` captures `systemd-analyze` and ES timeline
markers on every boot. The breakdown:

```
Kernel:           3.8s   (can't do much here)
Systemd:          8.4s   (device detection + service chain)
ES script init:   0.5s   (audio, brightness, config)
ES binary:       ~17s    (THE MONSTER — theme loading, Mesa init, directory scanning)
───────────────────────
Total:           ~29s
```

**The systemic fixes (35s → 29s):**

*Removed splash.service:*
U-Boot already shows `logo.bmp` at power-on (via `lcd_show_logo()` in `rk_board_late_init()`).
Our splash.service was showing the image a second time. Removed it — one less service, one less
flash. Updated `logo.bmp` to the new ArchR dragon logo (2400x1792 PNG → 640x480 24bpp BMP).

*Replaced getty+bash with systemd service (the big one — saved ~5s):*
Investigated how dArkOS achieves 21s. Their key difference: ES launches via a systemd service,
not through the getty → PAM → bash → profile.d → .bash_profile chain. That chain alone costs
4+ seconds on our slow SD card (bash binary loading from ext4 on a Class 10 card is brutal).

Created `emulationstation.service`: `Type=simple`, `User=archr`, environment variables set
directly (no fork overhead), `TTYPath=/dev/tty1` for DRM master access.

Masked `getty@tty1.service` (→ /dev/null). Removed the fast-path exec block from `/etc/profile`
(dead code now). Rewrote `emulationstation.sh` from 170 lines to 56 — removed root guard
(service handles user), 12 export statements (service handles env), mkdir/linking (build-time),
timing profiling, debug log setup. Kept: audio restore, brightness restore, save_state, main loop.

*Removed fbcon=rotate:0 from kernel cmdline:*
This parameter initializes the framebuffer console, which clears the U-Boot logo. Without it,
the logo persists through the entire kernel boot. ES handles display orientation via SDL/DRM,
fbcon isn't needed.

*Boot-setup optimized (415ms → 89ms):*
Removed `sleep 0.1` (was waiting for /dev/dri/* after modprobe panfrost). Created udev rules
(`99-archr.rules`) to set DRM/tty/backlight permissions automatically on device creation — no
more manual chmod. Added background readahead for ES binary + Mesa libraries (pre-warms the
page cache while other services are still initializing).

**The shutdown bug and its fix:**

The systemd service broke shutdown. ES calls `sudo systemctl poweroff` from the script, but
sudo needs CAP_SETUID/SETGID to switch to root — and the service only had CAP_SYS_ADMIN. The
log showed `sudo: unable to change to root gid: Operation not permitted`. Fixed by adding
CAP_SETUID, CAP_SETGID, CAP_DAC_OVERRIDE, CAP_AUDIT_WRITE to the service's
AmbientCapabilities. Also added `systemctl poweroff` and `systemctl reboot` to the NOPASSWD
sudoers list. And changed all exit paths to `exit 0` — previously `exit $ret` with ES's
non-zero exit code triggered `Restart=on-failure`, restarting ES instead of shutting down.

**The ROM detection bug:**

Games weren't showing in ES. Root cause: the ROMS partition (mmcblk1p3, FAT32) wasn't mounted
before ES started scanning directories. The fstab used `/dev/mmcblk1p3` with a 3-second device
timeout — but the device takes ~4.4s to appear. Fixed by switching to `LABEL=ROMS` (more
robust) and increasing the timeout to 10s. Added `After=local-fs.target` to the ES service
so it waits for all filesystem mounts.

**The remaining 17 seconds — ES binary startup analysis:**

Dove into the ES-fcamod source code to understand why the binary takes 17 seconds to show its
first frame. The startup sequence:

```
1. Window init (EGL/KMSDRM)              ~1-2s
2. Parse es_systems.cfg (XML)            ~0.5s
3. populateFolder() x 19 systems         ~3-4s   (walks /roms dirs)
4. loadTheme() x 19 systems              ~6-8s   (THE BOTTLENECK)
5. ViewController::preload() x 19        ~2-3s   (creates views)
6. First frame render                    ~0.5-1s
```

**The critical insight:** ES loads themes for ALL 19 systems defined in es_systems.cfg, even
though only 1 (SNES) has any ROMs. Each theme involves parsing potentially complex XML, resolving
variables, building element hierarchies for every view type. On a 1.5GHz Cortex-A35, this adds
up fast. dArkOS is faster partly because their Mali proprietary blob has near-zero GPU init
(vs our Panfrost shader compilation), but also because their theme loading is likely simpler.

Applied `PreloadUI=false` in es_settings.cfg — this skips the `preload()` loop that creates
views for all systems upfront (~2-3s saved). Views are created on-demand when the user
navigates to a system.

**What's next — ES lazy theme loading (the big fish):**

The real win is making ES lazy-load themes: only load the theme for the currently displayed
system, not all 19 at startup. This would save 6-8 seconds. Requires modifying
`SystemData::loadConfig()` in the ES-fcamod source to defer `loadTheme()` until first use,
and updating `ViewController::getGameListView()` to trigger theme loading on navigation. This
is a C++ source modification + recompilation — planned for the next session.

**Boot time progression:**
```
Day 1:    ~50s   (kernel 4.4 + custom init, no systemd)
Day 7:    ~40s   (kernel 6.6 + systemd, unoptimized)
Day 14:   ~35s   (splash service, getty chain, heavy ES script)
Today:    ~29s   (systemd service, slim script, readahead, no fbcon)
Target:   ~22s   (ES lazy-load themes, potential Mesa shader cache)
```

---

### 2026-02-18 — Day 15: ES Binary 7x Faster, The U-Boot Mystery

Today was about profiling. After days of guesswork about where the 29 seconds were going,
we finally have hard numbers — and the results flipped our assumptions upside down.

**ES binary: 17s → 2.5s — The ThreadPool discovery**

The full source audit of EmulationStation-fcamod revealed an insidious bottleneck hidden
in plain sight: `SystemData::loadConfig()` uses a ThreadPool to load systems in parallel,
with a wait callback that calls `renderLoadingScreen()` every 10ms. Sounds reasonable.
Except `renderLoadingScreen()` calls `Renderer::swapBuffers()`, which blocks on VSync.

Our panel runs at 78.2Hz → each VSync block is ~12.8ms. At 10ms poll interval, we get
~130 wake-up-and-block cycles during the ~1.3s of actual system loading. Each cycle pays
the full VSync penalty: 130 × 12.8ms = **~1.7 seconds** wasted on a progress bar nobody
sees (the loading screen is blank text on a small display, loads in under 2 seconds total).

Patch 19 changes the interval from 10ms to 500ms. The progress bar still updates ~5 times
during loading, but those 5 swapBuffers are the only ones that block. From 1.7s of VSync
overhead to ~65ms. Combined with patches 20 (skip non-existent ROM dirs) and 21 (lazy
MameNames via `std::call_once`), the ES binary now starts in **2.5 seconds**.

The profiling header (`ArchrProfile.h`, patch 18) uses `clock_gettime(CLOCK_MONOTONIC)`
to print sub-millisecond timestamps to stderr at 5 key boot points. The numbers:

```
[BOOT    0.0ms] start
[BOOT   47.3ms] before window.init       — 47ms: Log init, setup
[BOOT 1609.2ms] before loadConfig        — 1562ms: SDL + EGL + DRM + fonts
[BOOT 2157.4ms] after loadConfig         — 548ms: ThreadPool systems + themes
[BOOT 2494.3ms] UI ready                 — 337ms: ViewController goToStart
```

**But the user still measures 29 seconds from power-on.** If ES only takes 2.5s, and
kernel+systemd is ~12s, and the ES script adds ~0.5s... where are the other ~14 seconds?

**The U-Boot mystery**

The math doesn't add up: 3.8s (kernel) + 8.4s (systemd) + 0.5s (script) + 2.5s (ES) = 15.2s.
The user measures 29s. That leaves **~14 seconds** unaccounted for, and U-Boot is the only
remaining candidate.

We tried to capture a full timeline with `/proc/uptime` timestamps in `emulationstation.sh`
and `boot-timing.service`. First attempt failed: timeline wrote to `/tmp/es-timeline.txt`
which is tmpfs — data lost on shutdown. Second attempt: `sleep 20` in boot-timing service
was too long — user shut down before it finished writing. Fixed both: timeline now writes
to `/home/archr/es-timeline.txt` (persistent), sleep reduced to 5s.

Next boot will give us the definitive answer. If `script_start` shows uptime=14s, then
U-Boot is indeed taking ~14s. Possible causes: PanCho panel selection timeout, bootdelay,
40MB Image load from a slow SD card, DDR training. All investigatable.

**systemd service cleanup**

While investigating, audited all enabled systemd services. Found three quick wins:

1. **getty@tty1 disabled** — ES uses DRM directly, getty was starting then immediately
   getting killed by `Conflicts=` directive. Wasted 300-500ms on start+stop cycle.
2. **hotkeys + battery-led services** — had `After=getty@tty1.service` for no reason.
   Changed to `After=local-fs.target`. No more serial dependency on a dead service.
3. **Readahead preload removed** from archr-boot-setup.service. The `cat` of ES binary +
   Mesa libraries into page cache (26MB) was contending with ES's own library loading.
   ES naturally page-faults its libs during SDL init — the preload just caused double reads.

These won't dramatically change boot time (maybe ~1s combined), but they clean up the
dependency graph and remove unnecessary I/O during the critical boot path.

**Cross-compilation still broken**

Confirmed earlier finding: Ubuntu's cross-compiler (`aarch64-linux-gnu-gcc` 13.3) produces
binaries that SIGSEGV on real Cortex-A35 hardware but work fine under `qemu-aarch64-static`.
Root cause unclear (possibly GLIBC runtime differences or ABI subtlety). All builds must
go through the QEMU chroot — `quick-rebuild-es.sh` handles this transparently.

**What tomorrow brings**

Boot the R36S, wait 30 seconds, shut down, mount SD card. Read `es-timeline.txt` and
`boot-timing.txt`. These two files will tell us exactly how the 29 seconds are distributed
and where to focus next. If it's U-Boot, we need to look at the bootloader configuration
(bootdelay, PanCho timeout, SD read speed). If it's something else, the data will show.

The kernel config also has pending changes (CIF camera/RAID disabled) that need a rebuild.
That should shave ~0.5s off kernel probe time.

---

### 2026-02-19 — Day 16: Chasing the Seamless Boot, PanCho Retired

Yesterday we figured out U-Boot was eating ~14 seconds. Today we attacked.

**PanCho gets the axe: 29s → 26s**

The PanCho panel selector had two `sleep 3` calls totaling 6 seconds of pure waste. The user
decided to retire PanCho entirely — "a estratégia será outra" for multi-panel boot. We renamed
PanCho.ini to .disabled. Boot dropped from 29s to 26s immediately. U-Boot now takes ~11s
instead of ~14s, with the remaining time being hardware init (~3-4s) and loading the 40MB
kernel Image (~4s).

**The seamless splash research**

In parallel with hardware testing, two deep research agents ran: one for boot splash
persistence (how to keep the U-Boot logo visible through kernel boot), and one for drawing
a progress bar on the framebuffer.

The splash research uncovered something we should have caught earlier: the stock R36S DTBs
include a `drm-logo@0` reserved-memory region and `logo-memory-region` property on the display
subsystem — that's how the stock firmware has a seamless boot with no black flash. Our custom
DTS was missing both. Without them, the Rockchip DRM driver calls
`drm_aperture_remove_framebuffers()` and destroys the U-Boot logo, causing the black screen
gap that our splash.service was trying to fill.

**The fix: three changes, one kernel rebuild**

1. **DTS: `reserved-memory` + `drm-logo@0`** — U-Boot writes the logo framebuffer address
   into this node at runtime. The kernel's `rockchip_drm_show_logo()` reads it and preserves
   the framebuffer through DRM initialization. No more black flash.

2. **DTS: `&display_subsystem` + `logo-memory-region` + `route-dsi`** — Tells the kernel
   which connector the logo is displayed on (DSI panel via vopb). Without the route, the
   logo preservation code doesn't know where to display.

3. **Kernel config: `CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y`** — This is the other
   half of the puzzle. Even with the logo preserved through DRM init, fbcon would still
   clear the framebuffer when it initializes. Deferred takeover makes fbcon wait until
   actual text output happens. Since we boot with `quiet` and `console=ttyFIQ0` (serial),
   fbcon never touches the framebuffer. Logo stays on screen from U-Boot all the way to ES.

The expected result after rebuild: U-Boot logo.bmp appears → stays visible through kernel
boot → stays visible through systemd → ES takes DRM master and replaces with its own UI.
Zero black flashes. The only visual transition will be the ~16ms mode-set when SDL3 KMSDRM
takes DRM master.

**Progress bar: deferred**

The progress bar research was thorough (custom C program ~100 lines, mmaps /dev/fb0, draws
over the splash at specific coordinates, disappears naturally when ES takes DRM master).
But with the seamless logo fix, a progress bar becomes less critical — the user already sees
the logo throughout boot. We can add it later as polish.

**boot-timing.service: Type=oneshot was the bug**

Also discovered that our boot-timing.service was using `Type=oneshot`, which blocks
`multi-user.target` until ExecStart completes (including the 15s sleep!). This meant
`systemd-analyze` always reported "Bootup not yet finished" because the service itself
was preventing systemd from ever marking boot as finished. Changed to `Type=simple`.

**What's next**

Kernel rebuild needed with drm-logo revert and config trim.

---

### 2026-02-19 (cont.) — drm-logo DEAD, Kernel 40MB → 18MB

**The seamless splash dream dies**

After deep analysis of `rockchip_drm_logo.c`, the drm-logo approach is confirmed dead
for our U-Boot. The ODROID-Go U-Boot (2017.09) simply never fills the `drm-logo@0`
reserved-memory `reg` property — it stays `<0 0 0 0>`. When the kernel's
`init_loader_memory()` runs, `resource_size()` returns 0, function returns `-ENOMEM`.
But here's the nasty part: `rockchip_clocks_loader_protect()` (an arch_initcall_sync)
runs because our `route-dsi { status = "okay" }` exists, and it holds VOP/display clocks
in a "protected" state. With the logo code bailing out, those clocks are left in an
inconsistent state → SDL3 KMSDRM gets `ERROR: Could not restore CRTC`. The stock R36S
firmware uses Rockchip's proprietary U-Boot which HAS the logo code. Our ODROID U-Boot
doesn't and never will.

**Reverted all drm-logo DTS changes** — removed `reserved-memory` block and
`&display_subsystem` override. Kept `CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y`
(harmless, prevents fbcon text during `quiet` boot).

**The SIGPIPE bug — the real reason the kernel wasn't shrinking**

Ran `build-kernel.sh` to rebuild with the reverted DTS. The GPU config warnings were
back: "Panfrost GPU: NOT ENABLED", "Mali Midgard: STILL ENABLED". Investigated and found
a beautiful bug:

`build-kernel.sh` piped `merge_config.sh` output through `| grep | head -20` for display
filtering. With our expanded config fragment (200+ entries), more than 20 "Value of CONFIG_X
is redefined" messages were generated. After 20 lines, `head -20` exits → SIGPIPE cascades
through `grep` to `merge_config.sh` → the script dies MID-LOOP → the `cp -T` that writes
the merged .config NEVER RUNS → .config stays as the original defconfig.

This means our config trim (16 categories, 200 disabled entries) was **never being applied
to the kernel!** Every build was using the full defconfig with all the bloat.

Fix: capture merge output to variable first (`MERGE_LOG=$(...)`), then filter for display.
No pipe, no SIGPIPE.

**The result: Image 40MB → 18MB!**

With the config actually applied for the first time:
- **Kernel Image: 40MB → 18MB** (55% reduction!)
- **Modules: 30MB → 5.2MB** (83% reduction!)
- Panfrost GPU: ENABLED (module) — Mali Midgard: disabled

The 16 categories of trim removed: PCI/NVMe/SATA, Debug/Ftrace, Rockchip MPP for other SoCs,
Camera/ISP/DVB, Display HDMI/DP/LVDS, Ethernet/CAN, PHY for other SoCs, MTD, XFS/NFS/BTRFS,
Audio codecs (kept only RK817), Touchscreen, SoC CPU configs (kept only PX30), BCMDHD, and
miscellaneous bloat (USB-C TCPM, DWC3, EFI, ramdisk, etc.).

**Deployed to SD card.** New Image (18MB), new DTB (104K, drm-logo reverted), new modules
(5.2MB). Old Image backed up as Image.bak. `rg351mp-kernel.dtb` verified preserved (lesson
learned the hard way on day 14).

**What this means for boot time:**
The 18MB Image loads in ~1.8s from SD card (vs ~4s for 40MB) — that's ~2.2s saved in U-Boot
alone! Combined with PanCho removal (-3.5s) and any future bootdelay=0 (-1.0s), U-Boot could
drop from 14s to ~7-8s. Total boot from power-on to ES visible could hit ~22s.

**Hardware test needed** — the SD card is ready, just needs to be plugged in and booted.

---

### 2026-02-19 (cont.) — Splash Graveyard, Boot Confirmed at 19s

**Three splash approaches tried. Three failures.**

This session was supposed to be the "seamless boot" session. We had the `archr-splash.c` binary
ready (a minimal C program that reads a BMP and blits it to `/dev/fb0`), and the plan was to
show the logo via a systemd service early enough that it would persist until ES takes DRM master.

**Attempt 1: archr-splash.service (fbcon disabled)**

Disabled `CONFIG_FRAMEBUFFER_CONSOLE` in the kernel to prevent fbcon from ever touching the
framebuffer. Deployed `archr-splash` binary + service (WantedBy=sysinit.target). Rebuilt kernel,
deployed everything. Booted — splash didn't persist. Something else cleared fb0 between the
splash write and ES startup. Removed the service.

**Attempt 2: ROCKNIX approach (fbcon enabled, gettys masked)**

Researched how ROCKNIX does it. Their trick: keep `FRAMEBUFFER_CONSOLE=y` but remove ALL getty
services and disable `DEFERRED_TAKEOVER`. The splash persists because no getty writes to the
console. Applied this: re-enabled fbcon, masked 6 getty services + getty-generator, set logind
`NAutoVTs=0`, disabled DEFERRED_TAKEOVER. Rebuilt kernel, deployed. Boot — "Não funcionou."
The archr-splash service (now with ConditionPathExists=/dev/fb0) never ran.

Then began 30 minutes of increasingly desperate diagnostic service iterations: external scripts
logging to /boot (FAT32), to /tmp, to /var/log. Removed ConditionPathExists. Added
After=local-fs.target. Changed to inline bash -c. Added StandardOutput/StandardError. None
produced any log output. The external script version of archr-boot-setup.service simply does
not execute — the inline bash -c version works, but external scripts silently don't run.
Root cause never determined. After 30 minutes of debugging without results, decided to abandon
this approach.

**Attempt 3: splash in emulationstation.sh**

Considered calling archr-splash from emulationstation.sh, but this would add latency to the
ES startup path. Decided against — reverted to U-Boot-only boot.

**The revert**

Removed all splash artifacts: archr-splash binary, archr-splash.service, splash-debug.sh,
splash-diag.sh. Restored emulationstation.sh from repo. Restored archr-boot-setup.service to
original inline version.

**The collateral damage: audio + brightness persistence broke**

After the revert, volume and brightness were resetting to defaults on every reboot.
Root cause: the getty masks and logind.conf changes from Attempt 2 were still on the SD card.
Masking getty.target and all getty services + setting NAutoVTs=0 broke session management,
preventing the hotkey daemon from properly saving state.

Also found a secondary bug: `emulationstation.sh` always hardcoded `amixer -q sset 'DAC' 80%`
regardless of saved volume in `~/.config/archr/volume`.

**Fixes:**
- Removed all 7 getty mask symlinks (`/etc/systemd/system/getty@.service` → /dev/null, etc.)
- Restored `/etc/systemd/logind.conf` to default `[Login]` (empty)
- Fixed `emulationstation.sh` to read saved volume:
  ```bash
  VOL_SAVE="$HOME/.config/archr/volume"
  if [ -f "$VOL_SAVE" ]; then
      amixer -q sset 'DAC' "$(cat "$VOL_SAVE")%" 2>/dev/null
  else
      amixer -q sset 'DAC' 80% 2>/dev/null
  fi
  ```

Both confirmed working after fixes.

**The good news: 18MB kernel BOOTS! 19 seconds!**

Boot measured at **19 seconds on first power-on**, 24 seconds on
second boot. The 18MB kernel is confirmed working. Boot timing data from `/boot/boot-timing.txt`:

```
Kernel:           2.348s
Userspace:        7.679s
Total (systemd):  10.027s
ES script start:  9.74s uptime
ES UI ready:     ~13.1s uptime
```

That means U-Boot is taking ~6-7s (19s - 13.1s uptime). Down from ~14s before PanCho removal
and ~11s with PanCho removed but 40MB Image. The 18MB Image shaved another ~2s off U-Boot.
The 24s second boot is likely the charge-animation code in U-Boot checking battery state.

Top systemd blame: `dev-mmcblk1p2.device` (3.8s), `systemd-udev-trigger` (1.6s),
`zram-swap` (0.9s).

**Current boot breakdown (confirmed):**
```
U-Boot:    ~6-7s   (DDR, PMIC, SD, display, 18MB Image load)
Kernel:    ~2.3s
systemd:   ~7.7s   (SD device detection 3.8s is the bottleneck)
ES script: ~0.2s
ES binary: ~2.5s
TOTAL:     ~19s first boot, ~24s with charge-animation
```

**Splash status: DEAD.** Three approaches tried, none worked with ODROID U-Boot. The brief
blackout during DRM init (~16ms mode-set) will stay for now. User explicitly chose to move on.
Future option: investigate Plymouth or accept the current boot experience.

**Kernel config note:** The config fragment currently has `FRAMEBUFFER_CONSOLE=y` and
`# CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER is not set` (from Attempt 2). This is
harmless — fbcon is active but with `console=ttyFIQ0` and `quiet`, no text appears on screen.

---

### 2026-02-19 (cont.) — Plymouth: The Fourth Splash Attempt (also dead)

After marking splash as "dead" earlier today, we circled back to try Plymouth — the proper
Arch Linux boot splash daemon. The theory: Plymouth uses DRM/KMS natively, maintains DRM
master, has systemd integration, and is battle-tested. If anything could give us seamless
boot, it would be this.

**Plymouth on embedded ARM: nothing works out of the box**

The rabbit hole was deep. Plymouth's systemd services (`plymouth-start.service`,
`plymouth-quit.service`) have NO `[Install]` section — they're designed for initramfs hooks,
not `systemctl enable`. Manual symlinks into `sysinit.target.wants/` were required.

Then `--attach-to-session` (the default) expected a session from an initramfs Plymouth instance
that doesn't exist. Switched to `--no-daemon` with `Type=simple`. Then the daemon hung at
`ply_get_primary_kernel: opening /proc/consoles` — with only `console=ttyFIQ0` (serial),
Plymouth couldn't find a VT to render on. Added `console=tty1` to the cmdline.

Then the watermark image appeared but was rotated 90 degrees — because the panel is 480x640
portrait and VOP does the rotation at scanout. Plymouth's `DeviceRotation` config had zero
effect. Had to pre-rotate the watermark image. Then it was off-center because the spinner
theme's `WatermarkVerticalAlignment=.96` maps to the wrong side after VOP rotation. Changed
to `.5`.

**Plymouth actually worked!** The image appeared correctly for ~2 seconds before ES took over.
But there was a ~3 second black gap between U-Boot logo and Plymouth.

**Kernel rebuild with DEFERRED_TAKEOVER**

Rebuilt the kernel with `CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y`. Deployed the 18MB
Image to the SD card. Still black gap. Even disabled Plymouth entirely (kept only
`console=ttyFIQ0`) — still black gap.

**Root cause:** The rockchip-drm driver allocates a new zero-filled GEM buffer during
`rockchip_drm_fbdev_setup()`. This zeros fb0 regardless of DEFERRED_TAKEOVER (which only
controls fbcon text). The DRM driver probe itself clears whatever U-Boot had painted.

Plymouth adds ANOTHER modeset on top — extra gap, not less. The user correctly pointed out
that ROCKNIX manages to keep the logo visible, but ROCKNIX likely uses Rockchip's proprietary
U-Boot which has the `drm-logo` framebuffer preservation code that our ODROID U-Boot lacks.

**Verdict: splash is truly dead**

Four approaches tried over three days:
1. `archr-splash.c` + systemd service → service silently fails to run external scripts
2. ROCKNIX approach (getty masking) → broke audio/brightness persistence
3. `drm-logo` DTS reserved-memory → ODROID U-Boot never fills reg property
4. Plymouth DRM splash → works but introduces its own black gap

Removed all Plymouth references from build scripts (`build-rootfs.sh`, `build-image.sh`,
`config/boot.ini`, `scripts/emulationstation.sh`). Created `cleanup-plymouth-sd.sh` to
remove Plymouth remnants from the SD card (services, config, debug logs, cmdline params,
fstab tmpfs restore).

The boot experience stays as-is: U-Boot logo (6-7s) → brief black (~2s DRM init) → ES UI.
Not perfect, but functional. Moving on.

---

## What's Left for v1.0 Stable

### Critical — Must Work Before Release

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | ES rendering on screen | **WORKING** | GLES 1.0 native → Mesa TNL → Panfrost, 78fps stable |
| 2 | Audio output (ES) | **WORKING** | `use-ext-amplifier` DTS fix. ES music + bgsound confirmed |
| 3 | Game launch (RetroArch) | **WORKING** | Video, input, **audio ALL working** |
| 4 | Button/joystick in ES | **WORKING** | gpio-keys (17 buttons) + adc-joystick (4 axes) |
| 5 | Button/joystick in games | **WORKING** | udev joypad, autoconfig detected |
| 6 | Clean shutdown/reboot | **WORKING** | Systemd service + sudo caps + PMIC shutdown hook |

### High Priority — Expected for Release

| # | Task | Status | Notes |
|---|------|--------|-------|
| 7 | Volume control (hotkeys) | **WORKING** | DAC mixer + VOL+/VOL- hotkeys in ES |
| 8 | Brightness control | **WORKING** | Direct sysfs backlight (max=255), MODE+VOL hotkeys |
| 9 | Mesa 26 on-device | **WORKING** | gles1=enabled, glvnd=false, Panfrost GLES 3.1 |
| 10 | GPU 600MHz unlock | **WORKING** | 520→600MHz, zero overvolt, bin=2 silicon |
| 11 | RetroArch audio | **WORKING** | Fixed by `use-ext-amplifier` DTS property (same root cause as ES) |
| 12 | Boot time optimization | **19s confirmed** | 18MB kernel booting, U-Boot ~6-7s, ES ready @13.1s uptime |
| 13 | Panel selection (PanCho) | Not tested | 18 DTBOs generated, boot.ini integration |
| 14 | Full build from scratch | Not tested | `build-all.sh` end-to-end |

### Medium Priority — Can Ship Without, Fix in Updates

| # | Task | Status | Notes |
|---|------|--------|-------|
| 14 | WiFi connection | Not tested | NetworkManager + AIC8800 driver |
| 15 | Bluetooth pairing | Not tested | bluez installed |
| 16 | Battery LED indicator | Installed | Python service, needs hardware test |
| 17 | Sleep/wake | Not implemented | PMIC sleep pinctrl in DTS |
| 18 | OTA updates | Not implemented | Future feature |
| 19 | Theme customization | Default only | ES-fcamod default theme |
| 20 | Headphone detection | Not tested | archr-hotkeys.py ALSA switch |

### Low Priority — Post-Release

| # | Task | Status | Notes |
|---|------|--------|-------|
| 21 | Additional RetroArch cores | 19 installed | More via pacman/AUR |
| 22 | Custom ES theme | Not started | Arch R branded theme |
| 23 | PortMaster integration | Not started | Native Linux game ports |
| 24 | DraStic (DS emulator) | Not started | Proprietary, needs license |
| 25 | Scraper integration | Not started | ES metadata scraping |
| 26 | Wi-Fi setup UI | Not started | In-ES WiFi configuration |

---

## Path to v1.0

**Current phase:** Stabilization — 18MB kernel confirmed booting (19s), all core features working

1. ~~**Test gl4es + Panfrost rendering**~~ — **DONE.** ES renders on screen, Panfrost GPU confirmed
2. ~~**Fix audio card registration**~~ — **DONE.** rk817_int card registered (3-iteration fix chain)
3. ~~**Audio output + volume/brightness**~~ — **DONE.** Speaker, DAC hotkeys, brightness all working
4. ~~**Fix shutdown**~~ — **DONE then REGRESSED.** Systemd hook works, but kernel panic appeared
5. ~~**CPU 1512MHz unlock**~~ — **DONE.** `rockchip,avs = <1>` (dArkOS approach)
6. ~~**Build Mesa 26**~~ — **DONE.** Panfrost + LLVM, megadriver architecture
7. ~~**Test Mesa 26 on device**~~ — **DONE.** GLES 1.0 native, 78fps stable, EGL_BAD_ALLOC fixed
8. ~~**GPU 600MHz unlock**~~ — **DONE.** Zero overvolt, bin=2 silicon, +15.4% vs 520MHz
9. ~~**GLES 1.0 native rendering**~~ — **DONE.** Eliminated gl4es entirely, +26% GPU perf
10. ~~**FPS stability fix**~~ — **DONE.** popen() fork overhead → sysfs direct reads, 78fps stable
11. ~~**Build RetroArch with KMSDRM**~~ — **DONE.** v1.22.2, KMS/DRM + EGL + GLES, 16MB binary
12. ~~**Validate game launch**~~ — **DONE.** Video works, input works, returns to ES cleanly
13. ~~**Rebuild ES with audio logging**~~ — **DONE.** Patch 15 confirmed software chain working perfectly
14. ~~**Fix audio (ES + RetroArch)**~~ — **DONE.** Root cause: missing `use-ext-amplifier` DTS property
15. ~~**Fix shutdown kernel panic**~~ — **TRANSIENT.** Not reproduced since Feb 15
16. ~~**Boot optimization (35s → 29s)**~~ — **DONE.** Systemd ES service, readahead, udev rules, slim script
17. ~~**Fix shutdown from systemd service**~~ — **DONE.** Sudo caps, NOPASSWD sudoers, exit 0 paths
18. ~~**Fix ROM detection**~~ — **DONE.** LABEL=ROMS in fstab, 10s device timeout
19. ~~**ES source optimization (21 patches)**~~ — **DONE.** ES binary 17s → 2.5s (7x faster). ThreadPool VSync, skip empty dirs, MameNames lazy
20. ~~**systemd service cleanup**~~ — **DONE.** getty disabled, dependency chain fixed, preload removed
21. ~~**Boot profiling: read es-timeline.txt**~~ — **DONE.** U-Boot ~11s (was ~14s pre-PanCho)
22. ~~**Boot: investigate U-Boot**~~ — **DONE.** PanCho removed (-3s), 26s measured
23. ~~**Seamless boot splash DTS**~~ — **FAILED + REVERTED.** drm-logo incompatible with ODROID U-Boot (never fills reg property)
24. ~~**Kernel config trim**~~ — **DONE.** 40MB → 18MB Image, 30MB → 5.2MB modules, 16 categories trimmed
25. ~~**Kernel rebuild + deploy**~~ — **DONE.** DTS drm-logo reverted + config trim. Deployed to SD card
26. ~~**Boot hardware test**~~ — **DONE.** 18MB kernel boots, 19s first boot confirmed
27. **Full build test** — Run `build-all.sh` end-to-end on clean environment
26. **Polish** — Panel selection, VT flash fix, theme, progress bar, final tweaks
27. **Release candidate** — Generate final image, test on multiple R36S units

## Stats

| Metric | Value |
|--------|-------|
| Project start | 2026-02-04 |
| Days active | 16 |
| Boot time | **19s** first boot (confirmed), 24s second boot (charge-animation) |
| Kernel Image size | 18MB (was 40MB, -55%) |
| Kernel version | 6.6.89-archr |
| CPU frequency | 1512MHz (unlocked from 1200) |
| GPU frequency | 600MHz (unlocked from 480) |
| DRAM frequency | 786MHz (unlocked from 666) |
| ES FPS | 78fps stable (panel 78.2Hz) |
| ES rendering | GLES 1.0 → Mesa TNL → Panfrost |
| ES audio | Working (SDL_mixer → SDL3 → ALSA → rk817) |
| RetroArch rendering | GLES 3.1 → Panfrost |
| RetroArch audio | Working (ALSA → rk817 → ext amp) |
| Panel support | 18 panels (6 original + 12 clone) |
| RetroArch cores | 18 pre-installed |
| Root causes found & fixed | 25+ |

---

*Last updated: 2026-02-19 (boot 19s confirmed, Plymouth also dead — 4 splash approaches tried, all failed with ODROID U-Boot)*
