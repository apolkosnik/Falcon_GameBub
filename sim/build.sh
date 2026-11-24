#!/bin/sh
# Builds the full-system simulation (Verilator): falcon_gamebub with all of
# its RTL, the SDRAM and SRAM models and the bench (sim/tb). OBJ=<dir> picks
# the object directory (default sim/obj_dir).
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
cd "$(dirname "$0")"
R=$(cd .. && pwd)/rtl
SRC="$R/falcon_gamebub.sv $(ls $R/gamebub/*.sv) $(ls $R/falcon/*.sv $R/falcon/*.v $R/falcon/dsp/*.sv) $(ls $R/ap68030/*.v)"
verilator --cc --exe --build --no-timing --no-assert-case -j ${JOBS:-16} -O3 --x-assign fast --x-initial fast \
	-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
	-Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-LATCH -Wno-COMBDLY -Wno-IMPLICIT -Wno-PINCONNECTEMPTY \
	-Wno-PROCASSWIRE -Wno-UNUSED -Wno-UNDRIVEN -Wno-DECLFILENAME -Wno-SYNCASYNCNET -Wno-INITIALDLY \
	--top-module tb_top -Mdir ${OBJ:-obj_dir} \
	-CFLAGS "-O2 -march=native" \
	rtl/xilinx_sim.sv rtl/sdram_sim.sv rtl/sram_sim.sv $SRC tb/tb_top.sv tb/sim_main.cpp "$@"
echo "built ${OBJ:-obj_dir}/Vtb_top"
