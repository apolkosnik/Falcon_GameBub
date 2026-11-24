#!/bin/sh
# Unit test of gb_sdram against the SDRAM model: run_sdr.sh [commands] [seed]
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
cd "$(dirname "$0")"
verilator --binary --timing -j 8 -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD \
	-Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-INITIALDLY --top-module tb_sdram -Mdir obj_sdr \
	tb_sdram.sv ../rtl/xilinx_sim.sv ../rtl/sdram_sim.sv ../../rtl/gamebub/gb_sdram.sv > obj_sdr.log 2>&1 || { tail -30 obj_sdr.log; exit 1; }
./obj_sdr/Vtb_sdram +cmds=${1:-20000} +seed=${2:-1}
