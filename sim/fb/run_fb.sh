#!/bin/sh
# Unit test of gb_fb (the frame store): run_fb.sh [plusargs], or with no
# arguments every case below.
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
cd "$(dirname "$0")"
if [ ! -x obj_fb/Vtb_fb ] || [ -n "$(find ../../rtl/gamebub/gb_fb.sv tb_fb.sv ../rtl/sram_sim.sv -newer obj_fb/Vtb_fb)" ]; then
	verilator --binary --timing -j 8 -O3 -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD \
		-Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-INITIALDLY --top-module tb_fb -Mdir obj_fb \
		tb_fb.sv ../rtl/xilinx_sim.sv ../rtl/sram_sim.sv ../../rtl/gamebub/gb_fb.sv > obj_fb.log 2>&1 || { tail -30 obj_fb.log; exit 1; }
fi
if [ $# -gt 0 ]; then exec ./obj_fb/Vtb_fb "$@"; fi
fail=0
for c in "+w=320 +h=240 +ce=2" "+w=320 +h=240 +ce=5 +dbl=1" "+w=320 +h=200 +ce=2" "+w=640 +h=480 +ce=5" \
         "+w=640 +h=400 +ce=1 +hblank=256 +vblank=90496" "+w=640 +h=400 +ce=2 +lace=1" "+w=320 +h=480 +ce=5" "+w=384 +h=240 +ce=2" \
         "+w=640 +h=200 +ce=2" "+w=320 +h=240 +ce=2 +hdmi=1" "+w=640 +h=480 +ce=5 +hdmi=1" \
         "+w=640 +h=240 +ce=2 +safe=1" "+w=320 +h=480 +ce=5 +safe=1" "+w=320 +h=240 +ce=2 +safe=1" \
         "+w=200 +h=240 +ce=2" "+w=160 +h=240 +ce=2" "+w=320 +h=120 +ce=2" "+w=200 +h=240 +ce=2 +hdmi=1"; do
	out=$(./obj_fb/Vtb_fb $c | grep -E "^gb_fb|PASS|FAIL")
	echo "$out" | head -1
	echo "$out" | grep -q PASS || fail=1
done
[ $fail = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
