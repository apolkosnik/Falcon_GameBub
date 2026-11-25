# Falcon (68060) variant

`apolkosnik.Falcon060`: the same Falcon with the
[AP68060](https://github.com/apolkosnik/Falcon_MiSTer/tree/main/rtl/AP68060) (a 68060 with
its caches, MMU and FPU) in place of the AP68030, as Falcon_MiSTer's Falcon060 build, and its
CT60 mode: a 32-bit bus and Fast RAM (TT-RAM) at `$01000000`, which EmuTOS and CT60-aware
software (CT60 TOS, MiNT, programs that use `Mxalloc`) find and use.

| | Falcon_MiSTer (Falcon060) | Game Bub |
|---|---|---|
| processor clock | 50 MHz | 47.97 MHz (MMCM CLKOUT5, asynchronous to the 31.98 MHz system clock) |
| Fast RAM | 64, 128 or 240 MB in DDR3 | 32 MB: the board's second SDRAM chip (setting **Fast RAM**: 32 MB or Off, taken at the next reset) |
| FPU | the AP68060's | the same |
| DSP | in | in |

With Fast RAM on, CT60 mode is on: the first 16 MB are the Falcon's map (and its mirror at
`$FF000000`), `$01000000-$02FFFFFF` the Fast RAM, everything else a bus error (how EmuTOS
finds the size). With Fast RAM off the processor sees the Falcon's 24-bit map. The CPU
setting of the 68030 build (Falcon 16 MHz timing) does not exist here: the 68060 always runs
at its own speed.

## Building

```
FALCON_MISTER=<Falcon_MiSTer checkout at rtl/falcon/UPSTREAM.md's commit> tools/build_variant.sh 060
```

stages `build/variant-060/tree` (this repository's framework, chisel, tools and
`rtl/gamebub`; `rtl/falcon` and `rtl/ap68060` imported by
`tools/import_falcon.py --variant 060`; `falcon_gamebub.sv` with `FALCON_CPU060`; the metadata
and `falcon060.xdc` of this directory) and builds it with Vivado 2018.3. The bitstream is
`build/variant-060/tree/build/FalconCore-gamebub_rev4/FalconCore-gamebub_rev4.bit`; with
`metadata/` it goes to `/cores/apolkosnik.Falcon060/` on the card.

What the import changes for the variant (`build/variant-060/tree/rtl/falcon/UPSTREAM.md`):

- `FALCON_CPU060` in `falcon_system.sv` (the AP68060 on `falcon_cpubus060`, `falcon_ddr_arb`
  sharing the DDR3 port with the Fast RAM's cache, no 68882 bridge);
- `falcon_cpubus060.sv`: Fast RAM size 1 is 32 MB (upstream: 64);
- `rtl/ap68060_ram.sv` and `rtl/ap030_l2ram.sv` here replace upstream's: the memories written
  as Vivado's templates. Upstream's, written for Quartus's inference, became flip-flops in
  Vivado 2018.3 (the caches alone 120,000 LUTs, the design 165,913 of 63,400);
- the AP68060's declarations moved before their first use (`tools/decl_before_use.py`).

`gb_sdram` puts beats with DDR3 address bits 24:21 not zero (guest `$01000000` up) in the
second chip (`CHIP1`: both chips initialised and refreshed, each with its own open rows; reads
of 1 to 4 beats: the Fast RAM's cache reads lines as two).

## Tests

- `sim/sdr/run_sdr.sh`: `gb_sdram` with one chip and with two (`CHIP1`), every beat read
  checked against a shadow, both SDRAM models' protocol and timing checks.
- `TREE=../build/variant-060/tree OBJ=obj_060 sim/build.sh` builds the full-system
  simulation of the variant (both SDRAM chips modelled). EmuTOS 1.4 boots with Fast RAM on:
  `ramtop` (`$5A4`) `$03000000`, `ramvalid` `$1357BD13` (as on MiSTer with its size), the
  screen the panel shows equal to Videl's frame, no SDRAM or SRAM model error.
- `sim/asm/fastram.s` (a bare ROM in place of TOS): longs, words and bytes in the Fast RAM's
  first and last megabyte read back, and `$03000000` must bus error.
