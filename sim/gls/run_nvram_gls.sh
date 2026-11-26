#!/bin/bash
# The NVRAM / real-time clock (falcon_nvram) in xsim, with tb_nvram_gls.sv
# (the Game Bub's reset and NVRAM restore, then the time read as TOS reads
# it, and the next second):
#   sim/gls/run_nvram_gls.sh rtl [plusargs]   the RTL
#   sim/gls/run_nvram_gls.sh gls [plusargs]   Vivado 2018.3's netlist of it,
#                                             synthesized out of context
# plusargs: -testplusarg reset_ms=<n> -testplusarg nvram=<hex file>
# Needs Vivado (VIVADO=/opt/tools/Xilinx/Vivado/2018.3).
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
VIVADO=${VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:-$(cd "$HERE/../.." && pwd)}
mode=${1:-gls}; shift || true
SRC="$TREE/rtl/falcon/falcon_nvram.sv"
W=${WORK:-$HERE/work_nvram_$mode}
mkdir -p "$W"; cd "$W"
source "$VIVADO/settings64.sh"
case $mode in
rtl)
	xvlog -sv $SRC "$HERE/tb_nvram_gls.sv" > xvlog.log
	xelab -debug off -timescale 1ns/1ps tb_nvram_gls -s sim > xelab.log
	;;
gls)
	if [ ! -f net.v ] || [ "$SRC" -nt net.v ]; then
		cat > syn.tcl <<TCL
set_param messaging.defaultLimit 100000
read_verilog -sv {$SRC}
synth_design -top falcon_nvram -part xc7a100tcsg324-1 -mode out_of_context -generic CLK_HZ=31979167
write_verilog -force -mode funcsim net.tmp.v
TCL
		rm -f net.v
		vivado -mode batch -source syn.tcl -log syn.log -nojournal > /dev/null
		mv net.tmp.v net.v
	fi
	xvlog net.v > xvlog_net.log
	xvlog -sv -d GLS "$HERE/tb_nvram_gls.sv" > xvlog.log
	xelab -debug off -timescale 1ns/1ps -L unisims_ver tb_nvram_gls glbl -s sim > xelab.log
	;;
*) echo "usage: $0 rtl|gls [plusargs]" >&2; exit 1 ;;
esac
xsim sim -R "$@"
