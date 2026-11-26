#!/bin/sh
# Runs the core's tests: the unit benches (gb_sdram, gb_fb), the DSP
# (sim/asm/dsptest.s, dspsnd.s, dspsndi.s: the host port, and the DSP's
# sound through the SSI, the crossbar and the DAC, every sample checked) and the
# full-system boots (EmuTOS from IDE, SCSI and floppy, running
# \AUTO\WRTEST.PRG, which writes WROTE.TXT back to the disk).
#   TOS=<EmuTOS 512 KB image> sim/run_tests.sh [unit|dsp|input|system|all]
# Needs Verilator 5, vasmm68k_mot, mtools. sim/build.sh first for the
# system tests. EmuTOS is free: https://emutos.sourceforge.io
# (etos512us.img of the 512 KB release).
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
cd "$(dirname "$0")"
what=${1:-all}
BIN=./${OBJ:-obj_dir}/Vtb_top
fail=0
if [ "$what" = unit ] || [ "$what" = all ]; then
	sdr/run_sdr.sh 20000 1 | grep -E "^gb_sdram|PASS|FAIL" | tee /dev/stderr | grep -q PASS || fail=1
	fb/run_fb.sh | grep -E "^gb_fb|ALL PASS|SOME FAILED" | tee /dev/stderr | grep -q "ALL PASS" || fail=1
fi
if [ "$what" = dsp ] || [ "$what" = all ]; then
	# bare test ROMs in place of TOS (sim/asm), on the whole core
	mkdir -p out
	(cd asm && for r in dsptest dspsnd dspsndi; do vasmm68k_mot -Fbin -quiet -o $r.rom $r.s; done)
	$BIN --tos asm/dsptest.rom --ms 300 --peek 1000 --peek 1004 --peek ffc > out/t_dsp_echo.log 2>&1 || true
	if grep -q "long at 001000: 00000010" out/t_dsp_echo.log && grep -q "long at 001004: 00000000" out/t_dsp_echo.log &&
	   grep -q "long at 000ffc: d0e0600d" out/t_dsp_echo.log && grep -q "^PASS" out/t_dsp_echo.log; then
		echo "dsp_echo: PASS (the host port: 16 of 16 words)"
	else
		echo "dsp_echo: FAIL (see sim/out/t_dsp_echo.log)"; fail=1
	fi
	for r in dspsnd dspsndi; do
		$BIN --tos asm/$r.rom --ms 300 --audio-ramp 50:8 > out/t_$r.log 2>&1 || true
		if grep -q "^PASS" out/t_$r.log; then echo "$r: PASS ($(grep '^audio ramp' out/t_$r.log))"
		else echo "$r: FAIL (see sim/out/t_$r.log)"; fail=1; fi
	done
fi
if [ "$what" = input ] || [ "$what" = all ]; then
	# sim/asm/padtest.s: the enhanced joystick ports (Jagpads, paddles) with
	# the controllers held by the bench. Positive: slot 0 A, Up, Start and its
	# left stick at (100, -50) (past the joystick threshold: right too), slot 1
	# B, X, Select, Left and (-128, 127) (down too). Negative: slot 0 B, X,
	# Select (B and X stay the mouse's button and a key, not Jagpad B and C),
	# slot 1 inactive with every button held (nothing on port B, paddles
	# centred). Rows: port A 0-3, port B 0-3, {buttons, directions} each.
	mkdir -p out
	(cd asm && vasmm68k_mot -Fbin -quiet -o padtest.rom padtest.s)
	pk="--peek 1000 --peek 1004 --peek 1008 --peek 100c --peek 1010 --peek 1014 --peek 1018 --peek 101c --peek 1020 --peek 1024 --peek ffc"
	for c in "on|--pad0 411:100:-50 --pad1 846:-128:127|bffcf6ff bfffffff bfffffff bfffffff bfff9fff bff7ffff bff7ffff bff7ffff ff3dff17 ff04ff43" \
	         "off|--pad0 806:0:0 --pad1-idle fff:50:50|bfffffff bfffffff bfffffff bffdffff bfffffff bfffffff bfffffff bfffffff ff24ff24 ff24ff24"; do
		n=${c%%|*}; r=${c#*|}; opt=${r%%|*}; want="${r#*|} d0e0600d"
		$BIN --tos asm/padtest.rom --ms 300 $opt $pk > out/t_pad_$n.log 2>&1 || true
		got=$(sed -n 's/^long at [0-9a-f]*: //p' out/t_pad_$n.log | tr '\n' ' ' | sed 's/ $//')
		if [ "$got" = "$want" ] && grep -q "^PASS" out/t_pad_$n.log; then echo "pads_$n: PASS"
		else echo "pads_$n: FAIL (got $got, want $want; see sim/out/t_pad_$n.log)"; fail=1; fi
	done
fi
if [ "$what" = system ] || [ "$what" = all ]; then
	[ -n "$TOS" ] || { echo "TOS=<EmuTOS 512 KB image> for the system tests" >&2; exit 1; }
	./make_media.sh > /dev/null
	mkdir -p out
	pids=""
	for c in ide:--ide0:hd.img scsi:--scsi0:hd.img fd:--fda:fd.st; do
		n=${c%%:*}; r=${c#*:}; opt=${r%%:*}; img=${r#*:}
		mkdir -p out/t_$n
		cp media/$img out/t_$n/disk.img
		$BIN --tos "$TOS" $opt out/t_$n/disk.img --write-back --ms ${MS:-8000} \
			--pc-every 500 --screens out/t_$n --screen-every 60 --check-screen > out/t_$n.log 2>&1 &
		pids="$pids $!"
	done
	wait $pids || true
	for n in ide scsi fd; do
		img=out/t_$n/disk.img
		[ $n = fd ] && spec="$img" || spec="$img@@1M"
		if grep -q "^PASS" out/t_$n.log && mtype -i "$spec" ::/WROTE.TXT 2>/dev/null | head -1 | grep -q "Written by the Falcon core"; then
			echo "boot_$n: PASS ($(grep -E '^end' out/t_$n.log | cut -c1-120))"
		else
			echo "boot_$n: FAIL (see sim/out/t_$n.log)"; fail=1
		fi
	done
fi
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
