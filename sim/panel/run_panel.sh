#!/bin/bash
# The panel test (sim/panel/tb_panel.sv): the framework's generated
# HandheldTop with the whole Falcon core, the rev 4 panel's pins checked.
# Uses the Verilog of the last build (build/FalconCore-gamebub_rev4/
# generated, made by the framework's flow: ./mill or tools/build_vivado2018.sh).
#   sim/panel/run_panel.sh [+w=320 +h=240 +dbl=1] [+still] [+frames=N]
# Needs Verilator 5 and Vivado's XPM sources.
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SIM=$(dirname "$HERE")
ROOT=$(dirname "$SIM")
GEN=$ROOT/build/FalconCore-gamebub_rev4/generated
FW=$ROOT/framework/verilog
XPM=${XILINX_VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}/data/ip/xpm
OBJ=$HERE/obj_panel
[ -f "$GEN/filelist.f" ] || { echo "no $GEN: build the core first" >&2; exit 1; }
if [ ! -x "$OBJ/tb_panel" ] || [ -n "$(find "$GEN" "$ROOT/rtl" "$HERE/tb_panel.sv" -newer "$OBJ/tb_panel" -name '*.sv' -o -newer "$OBJ/tb_panel" -name '*.v' | head -1)" ]; then
	GENFILES=()
	while read -r f; do [ -n "$f" ] && GENFILES+=("$GEN/$f"); done < "$GEN/filelist.f"
	R=$ROOT/rtl
	CORE=("$R/falcon_gamebub.sv" $(ls $R/gamebub/*.sv $R/falcon/*.sv $R/falcon/*.v $R/falcon/dsp/*.sv $R/ap68030/*.v))
	verilator --binary --timing -j "$(nproc)" -O2 --top-module tb_panel --Mdir "$OBJ" -o tb_panel \
		--no-assert-case --x-assign fast --x-initial fast \
		-Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING -Wno-TIMESCALEMOD \
		-Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-IMPLICIT \
		-Wno-PROCASSWIRE -Wno-SYNCASYNCNET -Wno-DEFPARAM -Wno-IMPLICITSTATIC -Wno-INITIALDLY \
		-Wno-MULTITOP -Wno-ASCRANGE -Wno-SELRANGE -Wno-ZERODLY \
		--timescale 1ns/1ps +define+TB_TOP=tb_panel +define+ONESPIN \
		"$XPM/xpm_cdc/hdl/xpm_cdc.sv" "$XPM/xpm_memory/hdl/xpm_memory.sv" "$XPM/xpm_fifo/hdl/xpm_fifo.sv" \
		"${GENFILES[@]}" "$FW/handheld/pll_reset_generator.sv" \
		"$SIM/rtl/xilinx_sim.sv" "$SIM/rtl/sram_sim.sv" "${CORE[@]}" "$HERE/tb_panel.sv" \
		> "$HERE/build.log" 2>&1 || { grep -m20 -E "%Error" "$HERE/build.log"; tail -5 "$HERE/build.log"; exit 1; }
fi
"$OBJ/tb_panel" "$@" | tee "$HERE/run.log"
grep -q '^PASS' "$HERE/run.log"
