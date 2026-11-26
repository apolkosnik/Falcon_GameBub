# Atari Falcon030 for Game Bub

An Atari Falcon030 core for the [Game Bub](https://gamebub.net/) handheld (rev 4,
XC7A100T), ported from [Falcon_MiSTer](https://github.com/apolkosnik/Falcon_MiSTer) to the
[Game Bub core framework](https://docs.gamebub.net/developing-cores/overview/)
(v1.1.0-beta5).

The machine is Falcon_MiSTer's own RTL, imported unchanged except for the few edits listed
in [rtl/falcon/UPSTREAM.md](rtl/falcon/UPSTREAM.md): the
[AP68030](https://github.com/apolkosnik/AP68030) (a pin-level MC68030 with its caches and
PMMU, at 32 MHz or the Falcon's 16 MHz timing), Videl, the DSP56001, DMA sound and the
crossbar, the YM2149, the MFP, the ACIAs and IKBD, the blitter, the NVRAM/RTC, the floppy
controller, IDE and SCSI. What the MiSTer's ARM and its framework do around the machine is
done here by the FPGA itself, and the Game Bub's MCU only loads and saves files.

**Status: experimental, not yet run on a Game Bub.** In full-system simulation (Verilator,
the whole core with models of the board's SDRAM and SRAM and of the firmware) EmuTOS 1.3
boots; see *Simulation*. The bitstream is built with Vivado 2018.3; see *Building* for its
timing.

## The 68060 variant

`releases/apolkosnik.Falcon060/` is the same Falcon with the AP68060 (68060 with its caches,
MMU and FPU, at 47.97 MHz) and CT60 mode's Fast RAM: 48 MB at `$01000000` (the first SDRAM chip's free
half and the second chip), as Falcon_MiSTer's Falcon060 build (which has 64 to 240 MB). For CT60 TOS, MiNT and
Fast RAM-aware software. See [variants/060/README.md](variants/060/README.md); it is built with
`tools/build_variant.sh 060`.

## Using the core

1. Copy `releases/apolkosnik.Falcon/` to `/cores/apolkosnik.Falcon/` on the microSD card.
2. Start the core and choose a TOS image (512 KB: TOS 4.0x, or the free
   [EmuTOS](https://emutos.sourceforge.io) `etos512*.img`, which also boots from IDE and SCSI
   disks without a driver). The core asks for it every time it starts.
3. Then the disks, all optional ("[No Selection]"): Floppy A and B (`.st`), IDE master and
   slave, SCSI 0 and 1 (`.vhd`, `.img`, `.hdf`: whole-disk images, as on MiSTer), and a
   cartridge image (`.stc`, `.img`, `.rom`, up to 128 KB).

Disk images stay on the card: the core reads and writes the sectors the Falcon asks for
with the framework's on-demand file commands, so what the Falcon writes is in the file
straight away. The NVRAM is kept in `falcon.nvram` (the 50 bytes MiSTer's and Hatari's
`.nvram` files have) in the core's folder: it is written back when the core is left.

### Controls

| Game Bub (or the first dock controller) | Falcon |
|---|---|
| D-pad, left stick | joystick in port 1 (the games' port) |
| A | its fire button |
| right stick | moves the mouse |
| R | left mouse button |
| B | right mouse button |
| L (held) | the D-pad moves the mouse, A and B are its buttons |
| X, Y, Start, Select | keys chosen in the settings (default Space, Return, Help, Esc) |
| Start, Select | also the Jagpad's Pause and Option on enhanced port A |
| left stick | also the paddles of enhanced port A |
| second dock controller | joystick in port 0 (the mouse port), and the Jagpad of enhanced port B as Falcon_MiSTer maps a pad: A fire / A, B button B (and Space), X button C (and autofire), Start Pause, Select Option; its left stick the paddles of enhanced port B |
| USB keyboard / mouse on the dock | the Falcon's keyboard and mouse: needs the firmware fork and [firmware/](firmware/README.md) |

### Settings

| Setting | |
|---|---|
| Reset | resets the Falcon |
| Monitor | VGA (default), RGB, TV, Mono (SM124): what TOS sees; taken at the next reset |
| ST-RAM | 14 MB or 4 MB; taken at the next reset |
| CPU | 32 MHz turbo, or the Falcon's 16 MHz (8 MHz by $FF8007) with Hatari's bus timing |
| X / Y / Start / Select key | Space, Return, Esc, Help (F11), Undo (F12), Tab, Alternate, Control |
| Mouse speed | for the sticks and the D-pad |
| SRAM timing | Normal (two clocks a word) or Safe (three): see *The picture* |
| Cold reset | resets the Falcon as at power on (TOS's warm start flag cleared) |
| Reset NVRAM | the NVRAM's defaults, then a reset |

## Limitations

* No FPU: a 68882 does not fit; on MiSTer its arithmetic runs on the ARM. Programs see a
  Falcon without one (F-line), as most Falcons were sold.
* No SCSI CD-ROM (it needs MiSTer's Main for its responses), no MIDI or serial port, no
  microphone, no real-time clock (TOS gets a fixed date; the NVRAM keeps its settings).
* The YM2149's channels are mixed linearly (Hatari's `YM_LINEAR_MIXING`): the 32768-entry
  table of the MiSTer core would take 15 of the FPGA's block RAMs.
* Hard disks and floppies are read a request at a time (a few milliseconds each), with no
  read-ahead yet.
* The picture: see below.

## The picture

The panel and HDMI do not show Videl's signal: the core keeps the Falcon's picture at its
own resolution in a frame store (`rtl/gamebub/gb_fb.sv`) and scales it for each screen.

* Videl's pixels are taken one per Falcon pixel, and doubled lines once (a 320 x 240 VGA
  screen, sent as 480 lines, is kept as 240); interlaced fields are woven. Width and height
  are measured every frame, so every Falcon mode works without settings. Colours are kept as
  RGB 5:6:5 (the Falcon's true colour; its palette's 6-bit red and blue lose their last bit).
* The store is the board's 512 KB SRAM and 45,056 words of block RAM: 307,200 pixels.
  Pictures of up to 153,600 pixels (320 x 200/240/480, 384 x 240, 640 x 200/240) have two
  frames, and the frame on the panel is never written while it is shown. Bigger ones
  (640 x 400, 640 x 480) and interlaced ones have one frame, written while it is shown:
  where the picture moves, a frame can show a diagonal seam.
* Panel (the 720 x 480 that rev 4 shows): whole factors, horizontally 800 / width and
  vertically 480 / height (at most 4, neither more than twice the other), centred. 320 x 200
  is 640 x 400, 640 x 480 is shown one to one, 384 x 240 overscan at 768 x 480 loses 24
  columns at each side.
* HDMI (1280 x 720): the panel's picture made 1.5 times bigger (nearest pixel), centred.
* The panel's driver is built for 60 Hz frames: RGB's 50 Hz frames are shown as they come,
  the mono monitor's 71 Hz ones faster than the panel shows them (some are not shown).
* With the Safe SRAM timing the store has a third less bandwidth, enough for pictures of
  up to 153,600 pixels: 640 x 400 and 640 x 480 then show columns late (black).

## How it works

| Falcon_MiSTer (Falcon.sv) | Game Bub (rtl/falcon_gamebub.sv) |
|---|---|
| PLL, 32 MHz | MMCM: 31.979 MHz system clock (32 MHz -0.07 %), 95.94 MHz memory clock (3 x), 191.9 MHz SPI, display clock |
| DDR3 (falcon_memarb's DDRAM port) | `gb_sdram`: the same 64-bit port on the first SDRAM chip (32 MB, the Falcon's 16 MB space in its first half), rows kept open, CAS latency 3 |
| hps_io ioctl: TOS, cartridge | `gb_host`: the files through falcon_system's loader port |
| hps_io sd_*: Main_MiSTer serves the disks | `gb_disk`: the same block protocol, served from the image files with FileGetSize / FileRead / FileWrite / FileFlush |
| falcon_nvram_store | `gb_host`: the NVRAM file into falcon_nvram at the first run, read back live when saved |
| ascal, video_mixer | `gb_fb`: the frame store in the SRAM and block RAM |
| PS/2, joysticks | `gb_input`: buttons and sticks, the dock's USB keyboard (HID usages to PS/2 set 2, which falcon_ikbd translates as on MiSTer) and mouse |

Host (MCU) memory map: see the head of `rtl/gamebub/gb_host.sv` (TOS at 0x2000_0000, the
cartridge at 0x2100_0000, the disks' buffer at 0x3000_0000, the NVRAM file at
0x4000_0000, settings at 0x1040..106C; the dock's mouse and keyboard at the Minimig core's
0x1030..103C).

Resources (Vivado 2018.3, placed): 48,009 LUTs (76 %), 111.5 of 135 block RAMs, 20 DSPs.

## Building

Requirements: Vivado (the framework documents 2023.2; 2018.3 is what this core is built
with), a JDK (11 or later), Python 3.12 or 3.13, and the source of Falcon_MiSTer only to
re-import it.

```
git clone --recurse-submodules https://github.com/apolkosnik/Falcon_GameBub
cd Falcon_GameBub
tools/patch_framework.sh
./mill root.buildCore --target gamebub_rev4
```

The bitstream is `build/FalconCore-gamebub_rev4/FalconCore-gamebub_rev4.bit`.
`tools/build_vivado2018.sh` builds it with Vivado 2018.3 (the framework's flow, the two
`xpm_fifo_async` parameters 2018.3 does not have removed, timing-driven implementation
directives) and fails if timing is not met; `tools/vivado2018_env.sh` runs it with the
paths of the machine it was written on.

`patches/framework/` holds the framework changes of the Game Bub Minimig core that this core
uses (a core keeping its own frames and showing them through the external picture, 720p
HDMI); `tools/patch_framework.sh` applies them to the submodule.

`rtl/falcon/` and `rtl/ap68030/` are generated by `tools/import_falcon.py` from a pinned
commit of Falcon_MiSTer (`rtl/falcon/UPSTREAM.md`): include files and the opcode table of
the Falcon-mode prefetch model are written into the files, and the edits listed there made.

## Simulation

`sim/build.sh` builds a Verilator simulation of the whole core (`falcon_gamebub` and all of
its RTL) with the board's SDRAM (`sim/rtl/sdram_sim.sv`: every command's protocol and
timing checked, refresh included) and SRAM (`sim/rtl/sram_sim.sv`: the pins' timing checked
in half clocks), and a bench (`sim/tb/sim_main.cpp`) that plays the Game Bub around it: the
firmware's load sequence (TOS, the NVRAM file, settings, SetupComplete, CoreRun), its worker
loop serving the core's file commands on the image files, the framework's choice of frames,
and the panel or HDMI scanned through the external picture as their drivers do.

`sim/run_tests.sh` runs the tests (`TOS=<etos512us.img>`):

| Test | |
|---|---|
| `sim/sdr/run_sdr.sh` | `gb_sdram` against the SDRAM model: memarb's protocol at random (bursts of 1 and 4 beats, byte-masked writes, row misses in every bank), every beat read checked against a shadow copy, then 70 ms of refresh alone |
| `sim/fb/run_fb.sh` | `gb_fb` with the SRAM model and the framework's two sides: 14 cases (320 x 200, 320 x 240 sent doubled, 320 x 480, 384 x 240 cut at the sides, 640 x 200, 640 x 400 mono at 32 MHz pixels, 640 x 400 interlaced, 640 x 480 VGA; panel and HDMI; both SRAM timings), a new picture every frame, every pixel of every screen frame checked |
| `boot_ide`, `boot_scsi`, `boot_fd` | EmuTOS boots from a FAT16 hard disk on IDE, the same disk on SCSI, and a floppy, runs `\AUTO\WRTEST.PRG` (`sim/asm/wrtest.s`), which writes `WROTE.TXT`; the file must then be in the image (read with mtools), and the last screen must be Videl's last frame as `gb_fb` scales it |

`sim/make_media.sh` makes the disk images.

## License

GPL-2.0-or-later, as Falcon_MiSTer (the AP68030 is GPL-2.0). The Game Bub framework is
CERN-OHL-S-2.0. The modules in `rtl/gamebub/`, the framework patches and the simulation
models come from the author's Game Bub Minimig and 3DO cores and are licensed here under
GPL-2.0-or-later.
