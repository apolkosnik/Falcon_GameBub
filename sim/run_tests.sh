#!/bin/sh
# Runs the core's tests: the unit benches (gb_sdram, gb_fb) and the
# full-system boots (EmuTOS from IDE, SCSI and floppy, running
# \AUTO\WRTEST.PRG, which writes WROTE.TXT back to the disk).
#   TOS=<EmuTOS 512 KB image> sim/run_tests.sh [unit|system|all]
# Needs Verilator 5, vasmm68k_mot, mtools. sim/build.sh first for the
# system tests. EmuTOS is free: https://emutos.sourceforge.io
# (etos512us.img of the 512 KB release).
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
cd "$(dirname "$0")"
what=${1:-all}
fail=0
if [ "$what" = unit ] || [ "$what" = all ]; then
	sdr/run_sdr.sh 20000 1 | grep -E "^gb_sdram|PASS|FAIL" | tee /dev/stderr | grep -q PASS || fail=1
	fb/run_fb.sh | grep -E "^gb_fb|ALL PASS|SOME FAILED" | tee /dev/stderr | grep -q "ALL PASS" || fail=1
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
		./obj_dir/Vtb_top --tos "$TOS" $opt out/t_$n/disk.img --write-back --ms ${MS:-8000} \
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
