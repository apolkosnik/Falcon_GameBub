#!/bin/bash
# gb_fb as a netlist: Vivado 2018.3 synthesizes it for the board's FPGA out
# of context, and xsim runs the unit test of sim/fb (tb_fb.sv, the SRAM
# model, every pixel of the panel or HDMI checked) on the netlist.
#   sim/gls/run_fb_gls.sh [tb_fb plusargs, e.g. -testplusarg w=640 ...]
# Needs Vivado (VIVADO=/opt/tools/Xilinx/Vivado/2018.3).
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
VIVADO=${VIVADO:-/opt/tools/Xilinx/Vivado/2018.3}
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../.." && pwd)
W=${WORK:-$HERE/work_fb}
SRC="$TREE/rtl/gamebub/gb_fb.sv"
mkdir -p "$W"; cd "$W"
source "$VIVADO/settings64.sh"
if [ ! -f net.v ] || [ ! net.v -nt "$SRC" ]; then
	cat > syn.tcl <<TCL
set_param messaging.defaultLimit 100000
read_verilog -sv $SRC
synth_design -top gb_fb -part xc7a100tcsg324-1 -mode out_of_context
write_verilog -force -mode funcsim net.tmp.v
TCL
	rm -f net.v
	vivado -mode batch -source syn.tcl -log syn.log -nojournal > /dev/null
	mv net.tmp.v net.v
	rm -rf xsim.dir
fi
if [ ! -d xsim.dir/sim ] || [ "$TREE/sim/fb/tb_fb.sv" -nt xsim.dir/sim ]; then
	xvlog net.v > xvlog_net.log
	xvlog -sv -d GLS "$TREE/sim/rtl/sram_sim.sv" "$TREE/sim/fb/tb_fb.sv" > xvlog.log
	xelab -debug off -timescale 1ns/1ps -L unisims_ver tb_fb glbl -s sim > xelab.log
fi
xsim sim -R "$@"
