// The framework's generated HandheldTop (the Verilog the bitstream is built
// from: build/FalconCore-gamebub_rev4/generated, patched framework) with the
// whole Falcon core in it, and what reaches the rev 4 panel's pins.
//
// The Falcon itself stays in reset (no TOS is loaded); the bench puts a
// picture timed as Videl's in place of its video (the core's wires into
// gb_fb forced): 640 x 480 at VGA timing (a pixel on 4 of 5 clk_sys clocks,
// lines of 1017 clocks, 525 lines: 59.9 Hz), or with +w=320 +h=240 +dbl=1 a
// line-doubled low resolution. The picture changes every frame unless
// +still. The clocks are as on the board: clk_mem 95.94 MHz and clk_sys a
// third of it from the core's MMCM model, and the panel's dot clock at
// 959.375 MHz / 37 = 25.93 MHz, asynchronous to them.
//
// Every pixel of whole frames of the panel (the DPI pins: 800 lines of 480
// pixels, line L pixel P is column L - 12, row P of the core's 720 x 480)
// is compared with the picture as gb_fb scales it: the picture (one of the
// last four sent, or exactly the last with +still) centred, black around it.
// The report also says how many of the 720 columns showed any picture.
//
// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps

module tb_panel;

integer W, H, DBL, STILL, FRAMES;
initial begin
	if (!$value$plusargs("w=%d", W)) W = 640;
	if (!$value$plusargs("h=%d", H)) H = 480;
	if (!$value$plusargs("dbl=%d", DBL)) DBL = 0;
	STILL = $test$plusargs("still");
	if (!$value$plusargs("frames=%d", FRAMES)) FRAMES = 3;
end

// ---------------------------------------------------------------- clocks
localparam real T_MEM = 1000.0 / 95.9375;
reg clk_mem = 0, clk_sys = 0, mmcm_locked = 0;
integer ph = 0;
always #(T_MEM / 2.0) begin
	clk_mem = ~clk_mem;
	if (clk_mem) begin
		if (ph == 0) clk_sys = 1;
		ph = (ph + 1) % 3;
	end
	else if (ph == 2) clk_sys = 0;
end
initial #1000 mmcm_locked = 1;
reg clk_in_50mhz = 0;
always #10 clk_in_50mhz = ~clk_in_50mhz;
reg clk_dpi = 0;
always #(1000.0 / 25.929054 / 2.0) clk_dpi = ~clk_dpi;

// ---------------------------------------------------------------- the top
wire clk_sys_out, clk_sys_locked, reset;
pll_reset_generator sys_reset_gen(.clk(clk_sys_out), .clk_locked(clk_sys_locked), .reset(reset));
wire [1:0] sdram_cke, sdram_cs;
wire        lcd_vsync, lcd_hsync, lcd_enable;
wire  [7:0] lcd_r, lcd_g, lcd_b;
wire        sram_ce, sram_we, sram_oe, sram_dir;
wire  [1:0] sram_mask;
wire [17:0] sram_a;
wire [15:0] sram_q, sram_d;
wire [31:0] sram_errors;
// the board: the SRAM's pins change a little after the clk_mem edge
wire [17:0] p_a; wire [15:0] p_d; wire [1:0] p_mask; wire p_we, p_oe, p_dir;
assign #1.5 p_a = sram_a;
assign #1.5 p_d = sram_d;
assign #1.5 p_mask = sram_mask;
assign #1.5 p_we = sram_we;
assign #1.5 p_oe = sram_oe;
assign #1.5 p_dir = sram_dir;
sram_sim sram(
	.clk(clk_mem), .rd_need(4'd3), .wr_hold(1'b0),
	.ce_n(sram_ce), .we_n(p_we), .oe_n(p_oe), .mask_n(p_mask), .a(p_a),
	.din(p_d), .dir(p_dir), .dout(sram_q), .errors(sram_errors), .writes(), .reads()
);
HandheldTop dut(
	.clock(clk_sys_out), .reset(reset), .io_clockIn50Mhz(clk_in_50mhz),
	.io_clockOutSys(clk_sys_out), .io_clockOutDpi(), .io_clockOutLocked(clk_sys_locked),
	.io_clock_av(clk_dpi), .io_mcuIrq(),
	.io_mcuSpiChipSelect(1'b1), .io_mcuSpiClock(1'b0), .io_mcuSpiDataIn(4'h0), .io_mcuSpiDataOut(), .io_mcuSpiDataDir(),
	.io_lcd_vsync(lcd_vsync), .io_lcd_hsync(lcd_hsync), .io_lcd_enable(lcd_enable), .io_lcd_dotclk(),
	.io_lcdDataR(lcd_r), .io_lcdDataG(lcd_g), .io_lcdDataB(lcd_b),
	.io_dac_mclk(), .io_dac_wclk(), .io_dac_bclk(), .io_dac_data(),
	.io_hdmiEnable(), .io_hdmiClockPowerDown(), .io_hdmiAudioClock(), .io_hdmiAudio_0(), .io_hdmiAudio_1(),
	.io_hdmiRgb(), .io_hdmiCx(11'd0), .io_hdmiCy(10'd0),
	.io_buttons_a(1'b0), .io_buttons_b(1'b0), .io_buttons_x(1'b0), .io_buttons_y(1'b0),
	.io_buttons_up(1'b0), .io_buttons_down(1'b0), .io_buttons_left(1'b0), .io_buttons_right(1'b0),
	.io_buttons_l(1'b0), .io_buttons_r(1'b0), .io_buttons_start(1'b0), .io_buttons_select(1'b0),
	.io_cartridge3V3Enable(), .io_cartridge5V0Enable(), .io_cartridge_enabled(), .io_cartridge_switch(1'b0),
	.io_cartridge_bank0In(8'h0), .io_cartridge_bank1In(8'h0), .io_cartridge_bank2In(8'h0),
	.io_cartridge_bank3In(4'h0), .io_cartridge_pin30In(1'b0), .io_cartridge_pin31In(1'b0),
	.io_cartridge_bank0Out(), .io_cartridge_bank1Out(), .io_cartridge_bank2Out(), .io_cartridge_bank3Out(),
	.io_cartridge_pin30Out(), .io_cartridge_pin31Out(), .io_cartridge_bank0Dir(), .io_cartridge_bank1Dir(),
	.io_cartridge_bank2Dir(), .io_cartridge_bank3Dir(), .io_cartridge_pin30Dir(), .io_cartridge_pin31Dir(),
	.io_vibrate(), .io_pmod_in(4'h0), .io_pmod_out(), .io_pmod_dir(),
	.io_link_soIn(1'b0), .io_link_siIn(1'b0), .io_link_sdIn(1'b0), .io_link_scIn(1'b0),
	.io_link_soOut(), .io_link_siOut(), .io_link_sdOut(), .io_link_scOut(),
	.io_link_soDir(), .io_link_siDir(), .io_link_sdDir(), .io_link_scDir(),
	.io_sram_ceN(sram_ce), .io_sram_weN(sram_we), .io_sram_oeN(sram_oe), .io_sram_writeMaskN(sram_mask),
	.io_sram_address(sram_a), .io_sram_dataIn(sram_q), .io_sram_dataOut(sram_d), .io_sram_dataDir(sram_dir),
	.io_sdram_clock(), .io_sdram_cke(sdram_cke), .io_sdram_cs(sdram_cs), .io_sdram_ras(), .io_sdram_cas(),
	.io_sdram_we(), .io_sdram_dqm(), .io_sdram_bank(), .io_sdram_address(), .io_sdram_dataIn(16'h0),
	.io_sdram_dataOut(), .io_sdram_dataDir()
);

// ---------------------------------------------------------------- the picture
function automatic [23:0] pat(input integer fr, input integer x, input integer y);
	reg [31:0] h;
	h = (fr * 32'h9E3779B1) ^ (x * 32'h85EBCA6B) ^ (y * 32'hC2B2AE35);
	h = h ^ (h >> 13);
	h = h * 32'h27D4EB2F;
	pat = h[31:8] ^ h[23:0];
endfunction
function automatic [23:0] as565(input [23:0] c);
	as565 = {c[23:19], c[23:21], c[15:10], c[15:14], c[7:3], c[7:5]};
endfunction

reg        s_ce = 0, s_detb = 0, s_vb = 1;
reg  [7:0] s_r = 0, s_g = 0, s_b = 0;
integer    sframe = 0;
initial begin
	integer y, x, c, n, k;
	force dut.core.extModule.ce_pix = s_ce;
	force dut.core.extModule.vid_de_tb = s_detb;
	force dut.core.extModule.vblank = s_vb;
	force dut.core.extModule.vid_field = 1'b0;
	force dut.core.extModule.vid_lace = 1'b0;
	force dut.core.extModule.r = s_r;
	force dut.core.extModule.g = s_g;
	force dut.core.extModule.b = s_b;
	wait (reset === 1'b0);
	forever begin
		s_vb <= 1;
		repeat ((DBL ? 45 : 45) * 1017) @(posedge clk_sys_out);
		s_vb <= 0;
		for (y = 0; y < H; y = y + 1)
			for (k = 0; k <= DBL; k = k + 1) begin
				x = 0; c = 0;
				while (c < 1017) begin
					@(posedge clk_sys_out);
					c = c + 1;
					if (x < W && c % 5 != 0 && c >= 100) begin
						s_ce <= (W == 640) ? 1'b1 : (c % 2 == 0);
						if (W == 640 || c % 2 == 0) begin
							{s_r, s_g, s_b} <= pat(STILL ? 0 : sframe, x, y);
							x = x + 1;
						end
						s_detb <= (k == DBL);
					end
					else begin s_ce <= 0; if (x >= W) s_detb <= 0; end
				end
				s_detb <= 0;
			end
		sframe = sframe + 1;
	end
end

// ---------------------------------------------------------------- the panel
// expected: gb_fb's scaling (whole factors from 800 / W and 480 / H, at most
// 4, neither more than twice the other), centred in the 720 x 480
integer sx, sy, ex, ey, ox, oy;
always @* begin
	sx = (W <= 200) ? 4 : (W <= 266) ? 3 : (W <= 400) ? 2 : 1;
	sy = (H <= 120) ? 4 : (H <= 160) ? 3 : (H <= 240) ? 2 : 1;
	if (sx > 2 * sy) sx = 2 * sy;
	if (sy > 2 * sx) sy = 2 * sx;
	ex = W * sx; ey = H * sy;
	ox = (720 - ex) / 2; oy = (480 - ey) / 2;
end

reg        lv_d = 0, le_d = 0;
integer    line = -1, px = 0, pframes = 0, errors = 0, checked = 0;
reg        checking = 0;
reg [719:0] col_pic;              // columns that showed some of the picture
integer    ncols;
task automatic finish_report;
	ncols = 0;
	for (int i = 0; i < 720; i++) if (col_pic[i]) ncols++;
	$display("panel: %0d frames, %0d pixels checked, %0d wrong, %0d of the %0d picture columns showed picture pixels, SRAM model errors %0d; fb lines fetched %0d late %0d",
	         pframes, checked, errors, ncols, ex > 720 ? 720 : ex, sram_errors,
	         dut.core.extModule.dbg_lines, dut.core.extModule.dbg_late);
	$display((errors == 0 && sram_errors == 0) ? "PASS" : "FAIL");
	$finish;
endtask

always @(posedge clk_dpi) begin
	integer x, y, cx, k, ok, pxs, pys;
	reg [23:0] got, want;
	lv_d <= lcd_vsync;
	le_d <= lcd_enable;
	if (lcd_vsync && !lv_d) begin
		if (checking) begin
			pframes = pframes + 1;
			$display("panel frame %0d at %0t: %0d wrong so far", pframes, $time, errors);
			if (pframes >= FRAMES) finish_report();
		end
		checking <= (sframe >= 3);
		if (sframe >= 3) col_pic = '0;
		line <= -1;
	end
	else if (lcd_enable) begin
		x = le_d ? line : line + 1;
		y = le_d ? px : 0;
		if (!le_d) line <= line + 1;
		px <= y + 1;
		if (checking) begin
			got = {lcd_r, lcd_g, lcd_b};
			cx = x - 12;
			pxs = (cx >= ox && cx < ox + ex) ? (cx - ox) / sx : -1;
			pys = (y >= oy && y < oy + ey) ? (y - oy) / sy : -1;
			if (cx < 0 || cx >= 720 || pxs < 0 || pys < 0) begin
				ok = (got == 24'd0);
				want = 24'd0;
			end
			else begin
				ok = 0;
				for (k = 0; k < (STILL ? 1 : 5); k++) begin
					want = as565(pat(STILL ? 0 : sframe - k, pxs, pys));
					if (got == want) ok = 1;
				end
				if (got != 24'd0) col_pic[cx] = 1'b1;
			end
			checked = checked + 1;
			if (!ok) begin
				errors = errors + 1;
				if (errors <= 10) $display("ERROR panel line %0d pixel %0d (column %0d, row %0d): %h, want %h", x, y, cx, y, got, want);
			end
		end
	end
end

initial begin
	#2000000000;
	$display("timeout");
	finish_report();
end

endmodule
