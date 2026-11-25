#!/bin/sh
# Unit test of gb_sdram against the SDRAM models, with one chip (the 68030
# build) and two (the 68060 variant's Fast RAM): run_sdr.sh [commands] [seed]
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
cd "$(dirname "$0")"
for v in ${CHIPS:-1 2}; do
[ $v = 1 ] && D="+define+ONE_CHIP" || D=""
verilator --binary --timing -j 8 $D -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD \
	-Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-INITIALDLY --top-module tb_sdram -Mdir obj_sdr$v \
	tb_sdram.sv ../rtl/xilinx_sim.sv ../rtl/sdram_sim.sv ../../rtl/gamebub/gb_sdram.sv > obj_sdr$v.log 2>&1 || { tail -30 obj_sdr$v.log; exit 1; }
./obj_sdr$v/Vtb_sdram +cmds=${1:-20000} +seed=${2:-1}
done
