#!/bin/bash
# The DSP56001 and the sound crossbar (gls_dsp_top.sv: falcon_dsp and
# falcon_crossbar as falcon_system connects them) in xsim, with
# tb_dsp_gls.sv (the host port echo, and the DSP's sawtooth through the SSI,
# the crossbar and the DAC, polled and from the SSI interrupt, every sample
# checked):
#   sim/gls/run_dsp_gls.sh rtl [plusargs]   the RTL
#   sim/gls/run_dsp_gls.sh gls [plusargs]   Vivado 2018.3's netlist of it,
#                                           synthesized out of context for
#                                           the board's FPGA
# plusargs: -testplusarg step=<n> -testplusarg ms=<n>
# Needs Vivado (VIVADO=/opt/tools/Xilinx/Vivado/2018.3).
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
VIVADO=${VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:-$(cd "$HERE/../.." && pwd)}
mode=${1:-gls}; shift || true
D=$TREE/rtl/falcon/dsp
SRC="$D/dsp_ram.sv $D/dsp56k_rom.sv $D/dsp56k_dec.sv $D/dsp56k_alu.sv $D/dsp_periph.sv $D/dsp56k_core.sv $D/falcon_dsp.sv $TREE/rtl/falcon/falcon_crossbar.sv $HERE/gls_dsp_top.sv"
W=${WORK:-$HERE/work_dsp_$mode}
mkdir -p "$W"; cd "$W"
source "$VIVADO/settings64.sh"
case $mode in
rtl)
	# (VERILATOR: dsp_ram's contents zero at power up, as the block RAMs)
	xvlog -sv -d VERILATOR $SRC "$HERE/tb_dsp_gls.sv" > xvlog.log
	xelab -debug off -timescale 1ns/1ps tb_dsp_gls -s sim > xelab.log
	;;
gls)
	newest=$(ls -t $SRC | head -1)
	if [ ! -f net.v ] || [ "$newest" -nt net.v ]; then
		cat > syn.tcl <<TCL
set_param messaging.defaultLimit 100000
read_verilog -sv {$SRC}
synth_design -top gls_dsp_top -part xc7a100tcsg324-1 -mode out_of_context
report_utilization -file util.rpt
write_verilog -force -mode funcsim net.tmp.v
TCL
		rm -f net.v
		vivado -mode batch -source syn.tcl -log syn.log -nojournal > /dev/null
		mv net.tmp.v net.v
	fi
	xvlog net.v > xvlog_net.log
	xvlog -sv "$HERE/tb_dsp_gls.sv" > xvlog.log
	xelab -debug off -timescale 1ns/1ps -L unisims_ver tb_dsp_gls glbl -s sim > xelab.log
	;;
*) echo "usage: $0 rtl|gls [plusargs]" >&2; exit 1 ;;
esac
xsim sim -R "$@"
