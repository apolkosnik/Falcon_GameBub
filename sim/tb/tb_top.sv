// Full-system simulation of the Game Bub Falcon core: falcon_gamebub (the
// top level the framework binds, with all of its real RTL: the AP68030, the
// Falcon chipset, the DSP, gb_sdram, gb_disk, gb_fb, gb_host, gb_input),
// the SDRAM chip (sim/rtl/sdram_sim.sv: protocol and timing checked at every
// edge) and the SRAM (sim/rtl/sram_sim.sv).
//
// The C++ bench (sim_main.cpp) drives the clocks (the MMCM model in
// sim/rtl/xilinx_sim.sv hands clk_mem and clk_sys to gb_clocks), plays the
// Game Bub MCU on the HostV0 memory interface and both command channels as
// the framework presents them, plays the framework's choice of frames
// (frames.write / drop, external.frame) and scans the screen through the
// external picture as the panel's driver or HDMI does.
//
// SPDX-License-Identifier: GPL-2.0-or-later

module tb_top
(
	input         clk_mem,
	input         clk_sys,
	input         clk_av,
	input         clk_cpu,           // the 68060 variant's processor clock (MMCM CLKOUT5)
	input         mmcm_locked,
	input         reset,

	// HostV0
	input         host_mem_enable,
	input         host_mem_write,
	output        host_mem_done,
	input  [31:0] host_mem_address,
	output [31:0] host_mem_dataRead,
	input  [31:0] host_mem_dataWrite,
	input         host_cmd_request,
	output        host_cmd_busy,
	output        host_cmd_done,
	output        host_cmd_error,
	output        host_core_request,
	input         host_core_busy,
	input         host_core_done,
	input         host_core_error,

	// slot 0 and 1 buttons {select, start, r1, l1, right, left, down, up, y, x, b, a}
	input  [11:0] buttons,
	input         slot1_active,
	input  [11:0] buttons1,
	// sticks {slot 0 right Y, right X, left Y, left X}
	input  [31:0] sticks,

	// the framework's side of the picture
	output        video_de,
	output        video_hblank,
	output        video_vblank,
	input         frames_write,
	input         frames_drop,
	input         av_hdmi,
	input         av_sync,
	input         av_frame,
	input  [10:0] av_x,
	input   [9:0] av_y,
	output [23:0] av_color,

	// Videl's stream (as gb_fb takes it)
	output  [7:0] vid_r,
	output  [7:0] vid_g,
	output  [7:0] vid_b,
	output        vid_ce,
	output        vid_de_tb,
	output        vid_vblank,

	output [15:0] audio_left,
	output [15:0] audio_right,

	// checks and observation
	output [31:0] sd_model_errors,
	output [31:0] sram_errors,
	output [31:0] dbg_pc,
	output        dbg_falcon_reset,
	output        dbg_halted,
	output [31:0] dbg_fb,            // gb_fb {overflow, late, lines}
	output [31:0] dbg_geom
);

// ---------------------------------------------------------------- the core
wire        sd_clk, sd_ras, sd_cas, sd_we, sd_dir;
wire  [1:0] sd_cke, sd_cs, sd_dqm, sd_ba;
wire [12:0] sd_a;
wire [15:0] sd_dout, mdl_dout, mdl1_dout;
wire        mdl_oe, mdl1_oe;
wire        sr_ce, sr_we, sr_oe, sr_dir;
wire  [1:0] sr_mask;
wire [17:0] sr_a;
wire [15:0] sr_dout, sr_din;

falcon_gamebub #(.DISPLAY_DIVIDER(36)) dut
(
	.clock(clk_sys), .reset(reset), .clocks_clockIn50M(1'b0),
	.clocks_clockOutSystem(), .clocks_clockOutDisplay(), .clocks_clockOutSpi(), .clocks_locked(),
	.video_data_r(), .video_data_g(), .video_data_b(),
	.video_dataEnable(video_de), .video_vblank(video_vblank), .video_hblank(video_hblank), .video_fit(),
	.video_external_clock(clk_av), .video_external_active(1'b1), .video_external_hdmi(av_hdmi),
	.video_external_x(av_x), .video_external_y(av_y), .video_external_sync(av_sync),
	.video_external_frame(av_frame), .video_external_color(av_color), .video_external_enable(),
	.video_frames_write(frames_write), .video_frames_drop(frames_drop),
	.audio_left(audio_left), .audio_right(audio_right),
	.host_mem_enable(host_mem_enable), .host_mem_write(host_mem_write), .host_mem_done(host_mem_done),
	.host_mem_address(host_mem_address), .host_mem_dataRead(host_mem_dataRead),
	.host_mem_dataWrite(host_mem_dataWrite),
	.host_commandHost_request(host_cmd_request), .host_commandHost_busy(host_cmd_busy),
	.host_commandHost_done(host_cmd_done), .host_commandHost_error(host_cmd_error),
	.host_commandCore_request(host_core_request), .host_commandCore_busy(host_core_busy),
	.host_commandCore_done(host_core_done), .host_commandCore_error(host_core_error),
	.input_slots_0_active(1'b1), .input_slots_0_deviceType(4'd0),
	.input_slots_0_buttons_a(buttons[0]), .input_slots_0_buttons_b(buttons[1]),
	.input_slots_0_buttons_x(buttons[2]), .input_slots_0_buttons_y(buttons[3]),
	.input_slots_0_buttons_up(buttons[4]), .input_slots_0_buttons_down(buttons[5]),
	.input_slots_0_buttons_left(buttons[6]), .input_slots_0_buttons_right(buttons[7]),
	.input_slots_0_buttons_l1(buttons[8]), .input_slots_0_buttons_r1(buttons[9]),
	.input_slots_0_buttons_l2(1'b0), .input_slots_0_buttons_r2(1'b0),
	.input_slots_0_buttons_l3(1'b0), .input_slots_0_buttons_r3(1'b0),
	.input_slots_0_buttons_start(buttons[10]), .input_slots_0_buttons_select(buttons[11]),
	.input_slots_0_analog_leftX(sticks[7:0]), .input_slots_0_analog_leftY(sticks[15:8]),
	.input_slots_0_analog_rightX(sticks[23:16]), .input_slots_0_analog_rightY(sticks[31:24]),
	.input_slots_0_analog_leftTrigger(8'd0), .input_slots_0_analog_rightTrigger(8'd0),
	.input_slots_1_active(slot1_active), .input_slots_1_deviceType(4'd0),
	.input_slots_1_buttons_a(buttons1[0]), .input_slots_1_buttons_b(buttons1[1]),
	.input_slots_1_buttons_x(buttons1[2]), .input_slots_1_buttons_y(buttons1[3]),
	.input_slots_1_buttons_up(buttons1[4]), .input_slots_1_buttons_down(buttons1[5]),
	.input_slots_1_buttons_left(buttons1[6]), .input_slots_1_buttons_right(buttons1[7]),
	.input_slots_1_buttons_l1(buttons1[8]), .input_slots_1_buttons_r1(buttons1[9]),
	.input_slots_1_buttons_l2(1'b0), .input_slots_1_buttons_r2(1'b0),
	.input_slots_1_buttons_l3(1'b0), .input_slots_1_buttons_r3(1'b0),
	.input_slots_1_buttons_start(buttons1[10]), .input_slots_1_buttons_select(buttons1[11]),
	.input_slots_1_analog_leftX(8'sd0), .input_slots_1_analog_leftY(8'sd0),
	.input_slots_1_analog_rightX(8'sd0), .input_slots_1_analog_rightY(8'sd0),
	.input_slots_1_analog_leftTrigger(8'd0), .input_slots_1_analog_rightTrigger(8'd0),
	.sdram_clock(sd_clk), .sdram_cke(sd_cke), .sdram_cs(sd_cs), .sdram_ras(sd_ras), .sdram_cas(sd_cas),
	.sdram_we(sd_we), .sdram_dqm(sd_dqm), .sdram_bank(sd_ba), .sdram_address(sd_a),
	.sdram_dataIn(mdl_oe ? mdl_dout : mdl1_oe ? mdl1_dout : 16'h0000), .sdram_dataOut(sd_dout), .sdram_dataDir(sd_dir),
	.sram_ceN(sr_ce), .sram_weN(sr_we), .sram_oeN(sr_oe), .sram_writeMaskN(sr_mask),
	.sram_address(sr_a), .sram_dataIn(sr_dout), .sram_dataOut(sr_din), .sram_dataDir(sr_dir)
);

// the first SDRAM chip at the board's clock (10.42 ns): the timing in clocks
sdram_sim #(.T_RCD(2), .T_RP(2), .T_RAS(5), .T_RC(7), .T_RFC(7), .T_REFI(749)) sdram
(
	.clk(sd_clk), .cke(sd_cke[0]), .cs_n(sd_cs[0]), .ras_n(sd_ras), .cas_n(sd_cas), .we_n(sd_we),
	.ba(sd_ba), .a(sd_a), .dqm(sd_dqm), .dq_in(sd_dout), .dq_in_en(sd_dir),
	.dq_out(mdl_dout), .dq_out_en(mdl_oe)
);

`ifdef FALCON_CPU060
// the second chip: the 68060 variant's Fast RAM
sdram_sim #(.T_RCD(2), .T_RP(2), .T_RAS(5), .T_RC(7), .T_RFC(7), .T_REFI(749)) sdram1
(
	.clk(sd_clk), .cke(sd_cke[1]), .cs_n(sd_cs[1]), .ras_n(sd_ras), .cas_n(sd_cas), .we_n(sd_we),
	.ba(sd_ba), .a(sd_a), .dqm(sd_dqm), .dq_in(sd_dout), .dq_in_en(sd_dir),
	.dq_out(mdl1_dout), .dq_out_en(mdl1_oe)
);
wire [31:0] mdl1_errors = sdram1.errors;
wire        chip1_ok = 1'b1;
`else
assign mdl1_dout = 16'h0000, mdl1_oe = 1'b0;
wire [31:0] mdl1_errors = 32'd0;
wire        chip1_ok = 1'b0;   // the 68030 build never selects chip 1
`endif
reg [31:0] bus_errors = 32'd0;
always @(posedge sd_clk) begin
	if ((sd_dir && (mdl_oe || mdl1_oe)) || (mdl_oe && mdl1_oe)) bus_errors <= bus_errors + 32'd1;
	if (!chip1_ok && sd_cs[1] !== 1'b1) bus_errors <= bus_errors + 32'd1;
end
assign sd_model_errors = sdram.errors + mdl1_errors + bus_errors;

sram_sim sram
(
	.clk(clk_mem), .rd_need(dut.sram_safe ? 4'd5 : 4'd3), .wr_hold(dut.sram_safe),
	.ce_n(sr_ce), .we_n(sr_we), .oe_n(sr_oe), .mask_n(sr_mask), .a(sr_a),
	.din(sr_din), .dir(sr_dir), .dout(sr_dout), .errors(sram_errors), .writes(), .reads()
);

// ---------------------------------------------------------------- observation
assign vid_r      = dut.r;
assign vid_g      = dut.g;
assign vid_b      = dut.b;
assign vid_ce     = dut.ce_pix;
assign vid_de_tb  = dut.vid_de_tb;
assign vid_vblank = dut.vblank;
assign dbg_pc     = dut.system.dbg_pc;
assign dbg_falcon_reset = dut.falcon_reset;
assign dbg_halted = dut.system.cpu_halted;
assign dbg_fb     = {dut.dbg_overflow, dut.dbg_late[14:0], dut.dbg_lines};
assign dbg_geom   = dut.dbg_geom;

// guest memory for the bench: byte a of the Falcon's space
export "DPI-C" function guest_peek8;
function int unsigned guest_peek8(input int unsigned a);
	int unsigned beat, w;
	beat = a >> 3;
	// {bank, row, column}: column = beat[6:0] * 4 + word, bank beat[8:7], row beat[21:9]
	w = {16'd0, sdram.mem[{beat[8:7], beat[21:9], beat[6:0], a[2:1]}]};
	return a[0] ? (w >> 8) & 32'hFF : w & 32'hFF;
endfunction

endmodule
