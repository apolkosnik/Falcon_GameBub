// Unit bench of gb_fb: a Videl-like pixel stream (a new picture every frame)
// into the frame store, with the SRAM model, and the framework's two sides
// around it: its choice of the frame written, thrown away and shown
// (HandheldTop.scala with ownFrames), and the screen scanned as the panel's
// driver (columns of 480 rows) or HDMI (720p lines) scans it. Every pixel of
// every screen frame after the first few is checked against the picture:
//   - double-buffered frames on the panel: exactly the frame the framework
//     shows (on HDMI, which the framework lets the core write while it is
//     shown, as for one frame below);
//   - one frame (bigger or interlaced): the pixel as the picture being
//     written or one of the four before it (fields) wrote it (the screen may show a frame while it is
//     written);
//   - outside the picture: black.
// The scaling is computed here from the rules in gb_fb's header.
//   +w=W +h=H   the picture       +dbl=1  Videl sends every line twice
//   +lace=1     interlaced (h = the woven height)
//   +ce=N       a pixel every N clk_sys clocks (+ce=5: 4 of 5, VGA's rate)
//   +hdmi=1     the HDMI screen   +safe=1  the SRAM at three clocks a word
//   +screens=N  screen frames to check (default 4)
//   +hblank=N   clk_sys clocks after a line (120)  +vblank=N  of the vertical blank
// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ps/1ps
`define TB_TOP tb_fb

module tb_fb;

reg mmcm_locked = 1'b1;
integer W, H, DBL, LACE, CE, HDMI, SAFE, SCREENS, HBL, VBL;
initial begin
	if (!$value$plusargs("w=%d", W)) W = 320;
	if (!$value$plusargs("h=%d", H)) H = 240;
	if (!$value$plusargs("dbl=%d", DBL)) DBL = 0;
	if (!$value$plusargs("lace=%d", LACE)) LACE = 0;
	if (!$value$plusargs("ce=%d", CE)) CE = 2;
	if (!$value$plusargs("hdmi=%d", HDMI)) HDMI = 0;
	if (!$value$plusargs("safe=%d", SAFE)) SAFE = 0;
	if (!$value$plusargs("screens=%d", SCREENS)) SCREENS = 4;
	if (!$value$plusargs("hblank=%d", HBL)) HBL = 120;
	if (!$value$plusargs("vblank=%d", VBL)) VBL = 40 * 900;
end

// clocks: clk_mem 95.9375 MHz, clk_sys / 3 aligned, clk_av 25 MHz (panel)
// or 74.25 MHz (HDMI)
localparam integer TM = 10424;
reg clk_mem = 0, clk_sys = 0, clk_av = 0;
integer phase = 0;
always #(TM/2) begin
	clk_mem = ~clk_mem;
	if (clk_mem) begin
		if (phase == 0) clk_sys = 1;
		phase = (phase + 1) % 3;
	end
	else if (phase == 2) clk_sys = 0;
end
initial begin
	#1;
	forever #((HDMI ? 13468 : 40000) / 2) clk_av = ~clk_av;
end

reg reset = 1'b1, reset_mem = 1'b1;

// ---------------------------------------------------------------- Videl
reg        ce_pix = 0, de_tb = 0, vblank = 1, field = 0;
reg  [7:0] r = 0, g = 0, b = 0;
integer    vframe = 0;            // pictures (fields) sent
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

task automatic send_line(input integer fr, input integer y, input bit tb);
	integer x, c;
	x = 0; c = 0;
	while (x < W) begin
		@(posedge clk_sys);
		de_tb <= tb;
		c = c + 1;
		if ((CE == 5) ? (c % 5 != 0) : (c % CE == 0)) begin
			ce_pix <= 1;
			{r, g, b} <= pat(fr, x, y);
			x = x + 1;
		end
		else ce_pix <= 0;
	end
	@(posedge clk_sys); ce_pix <= 0; de_tb <= 0;
	repeat (HBL) @(posedge clk_sys);
endtask

// what is in the store: picture number per slot (double buffering)
integer slot_fr [0:1];
// the framework's side (clk_sys), as HandheldTop
reg  wr_index = 1'b1, last_complete = 1'b0, started = 0, drop_r = 0;
reg  shown = 1'b0;                 // the frame the panel shows (activeDisplayFrame)
wire conflict = !HDMI && (wr_index == shown);
wire wr_drop = started ? drop_r : conflict;
wire fw_de, fw_hblank, fw_vblank;
reg  fwv_d = 1'b1;
integer cur_fr [0:1];              // picture being written into each frame
always @(posedge clk_sys) begin
	fwv_d <= fw_vblank;
	if (!fw_vblank && fw_de && !started) begin
		started <= 1; drop_r <= conflict;
	end
	if (fw_vblank && !fwv_d) begin
		if (!drop_r && started) begin
			last_complete <= wr_index;
			slot_fr[wr_index] = cur_fr[wr_index];
			wr_index <= !wr_index;
		end
		started <= 0; drop_r <= 0;
	end
end

initial begin
	integer y, n, lines;
	slot_fr[0] = -100; slot_fr[1] = -100;
	repeat (20) @(posedge clk_mem);
	reset_mem = 0;
	@(posedge clk_sys); reset <= 0;
	forever begin
		// vertical blank
		vblank <= 1;
		repeat (VBL) @(posedge clk_sys);
		field <= LACE ? (vframe & 1) : 0;
		@(posedge clk_sys);
		vblank <= 0;
		cur_fr[wr_index] = vframe;
		lines = LACE ? H / 2 : H;
		for (n = 0; n < lines; n = n + 1) begin
			y = LACE ? 2 * n + (vframe & 1) : n;
			if (DBL) send_line(vframe, y, 0);
			send_line(vframe, y, 1);
		end
		vframe = vframe + 1;
	end
end

// ---------------------------------------------------------------- the store
wire [17:0] s_a;
wire [15:0] s_dout, s_din;
wire  [1:0] s_mask;
wire        s_ce, s_we, s_oe, s_dir;
reg  [10:0] av_x = 0;
reg   [9:0] av_y = 0;
reg         av_sync = 0, av_frame = 0;
wire [23:0] av_color;
wire [31:0] geom;
wire [15:0] lines_f, late;
wire        ovf;

gb_fb dut
(
	.clk_sys(clk_sys), .reset(reset), .ce_pix(ce_pix), .de_tb(de_tb), .vblank(vblank),
	.field(field), .lace(LACE[0]), .r(r), .g(g), .b(b),
	.wr_frame(wr_index), .wr_drop(wr_drop), .fw_de(fw_de), .fw_hblank(fw_hblank), .fw_vblank(fw_vblank),
	.clk_mem(clk_mem), .reset_mem(reset_mem), .sram_safe(SAFE[0]),
	.sram_ceN(s_ce), .sram_weN(s_we), .sram_oeN(s_oe), .sram_writeMaskN(s_mask), .sram_address(s_a),
	.sram_dataIn(s_dout), .sram_dataOut(s_din), .sram_dataDir(s_dir),
	.clk_av(clk_av), .av_hdmi(HDMI[0]), .av_sync(av_sync), .av_frame(av_frame),
	.av_x(av_x), .av_y(av_y), .av_color(av_color),
	.dbg_geom(geom), .dbg_lines(lines_f), .dbg_late(late), .dbg_overflow(ovf)
);

// the pins a little after the clock edge (I/O block registers)
wire [17:0] p_a;  wire [15:0] p_din; wire [1:0] p_mask; wire p_we, p_oe, p_dir;
assign #1500 p_a = s_a;
assign #1500 p_din = s_din;
assign #1500 p_mask = s_mask;
assign #1500 p_we = s_we;
assign #1500 p_oe = s_oe;
assign #1500 p_dir = s_dir;
wire [31:0] sram_err;
sram_sim sram
(
	.clk(clk_mem), .rd_need(SAFE ? 4'd5 : 4'd3), .wr_hold(SAFE[0]), .ce_n(s_ce), .we_n(p_we), .oe_n(p_oe), .mask_n(p_mask), .a(p_a),
	.din(p_din), .dir(p_dir), .dout(s_dout), .errors(sram_err), .writes(), .reads()
);

// ---------------------------------------------------------------- screen
// the expected colour of screen pixel (x, y) of a frame of w x h
integer e_sx, e_sy, e_w, e_h;
function automatic integer fitf(input integer v, input integer t2, input integer t3, input integer t4);
	fitf = (v <= t4) ? 4 : (v <= t3) ? 3 : (v <= t2) ? 2 : 1;
endfunction
task automatic scaling(input integer w, input integer h);
	e_w = w; e_h = h;
	e_sx = fitf(w, 400, 266, 200);
	e_sy = fitf(h, 240, 160, 120);
	if (e_sx > 2 * e_sy) e_sx = 2 * e_sy;
	else if (e_sy > 2 * e_sx) e_sy = 2 * e_sx;
endtask
// source pixel of screen pixel (x, y), or -1
task automatic src_of(input integer x, input integer y, output integer px, output integer py);
	integer ex, ey, ox, oy;
	if (!HDMI) begin
		ex = e_w * e_sx; ey = e_h * e_sy;
		ox = (720 - ex) / 2; oy = (480 - ey) / 2;     // the panel's 720 x 480 (rev 4)
		if (720 - ex < 0) ox = -((ex - 720 + 1) / 2);  // (an arithmetic shift: floor)
		px = (x < 720 && x >= ox && x < ox + ex) ? (x - ox) / e_sx : -1;
		py = (y >= oy && y < oy + ey) ? (y - oy) / e_sy : -1;
	end
	else begin
		ex = (e_w * 3 * e_sx + 1) / 2; ey = (e_h * 3 * e_sy + 1) / 2;
		ox = (1280 - ex) / 2; oy = (720 - ey) / 2;
		px = (x >= ox && x < ox + ex) ? (2 * (x - ox)) / (3 * e_sx) : -1;
		py = (y >= oy && y < oy + ey) ? (2 * (y - oy)) / (3 * e_sy) : -1;
	end
	if (px < 0 || py < 0) begin px = -1; py = -1; end
endtask

integer errors = 0, checked = 0, screens = 0, black_in = 0;
integer show_fr;                  // the picture shown (double buffering)
bit     single;
reg [10:0] hx [0:11];
reg  [9:0] hy [0:11];
reg        hv [0:11];
initial for (int i = 0; i < 12; i++) hv[i] = 0;

task automatic check(input integer x, input integer y);
	integer px, py, f, ok, k;
	reg [23:0] want;
	src_of(x, y, px, py);
	if (px < 0) begin
		if (av_color !== 24'd0) begin
			errors = errors + 1;
			if (errors < 20) $display("ERROR (%0d,%0d) outside the picture: %h", x, y, av_color);
		end
	end
	else begin
		ok = 0;
		if (!single) begin
			want = as565(pat(show_fr, px, py));
			ok = (av_color == want);
		end
		else for (k = 0; k < 5; k = k + 1) if (av_color == as565(pat(vframe - k, px, py))) ok = 1;
		if (!single && av_color == 24'd0 && want != 24'd0) black_in = black_in + 1;
		if (!ok) begin
			errors = errors + 1;
			if (errors < 20 || $test$plusargs("allerr")) $display("ERROR (%0d,%0d) = source (%0d,%0d) of picture %0d: %h, want %h",
			                          x, y, px, py, show_fr, av_color, want);
		end
	end
	checked = checked + 1;
endtask

reg checking = 0;
initial begin
	integer x, y, sx_n, sy_n, t, sk;
	sk = LACE ? 6 : 3;
	// wait until the store has the picture's layout (a frame or two)
	wait (vframe >= sk);
	forever begin
		// a screen frame: sync, then the scan
		@(posedge clk_av);
		av_sync <= 1;
		av_frame <= last_complete;
		shown = last_complete;
		// one frame, or HDMI (the framework does not keep the frame HDMI shows
		// from being written: there a pixel may be of a newer picture)
		single = (LACE || W * H > 153600 || HDMI);
		show_fr = slot_fr[last_complete];
		scaling(W, H);
		checking = (vframe >= sk + 1);
		if (!HDMI) begin
			// the panel: 10 blank columns of 504 clocks, then 800 columns (the
			// framework names 720 of them: x = column - 12 on rev 4; the
			// others' x mean nothing, here 720..799)
			repeat (10 * 504) @(posedge clk_av);
			av_sync <= 0;
			for (x = 0; x < 800; x = x + 1)
				for (y = 0; y < 504; y = y + 1) begin
					@(posedge clk_av);
					av_x <= x; av_y <= (y < 480) ? y : 10'd500;
					hv[0] <= (y < 480) && (x < 720) && checking;
				end
		end
		else begin
			// HDMI: lines 720..749 blank (the sync at 720), then 0..719
			for (y = 720; y < 750; y = y + 1)
				for (x = 0; x < 1650; x = x + 1) begin
					@(posedge clk_av);
					av_x <= x; av_y <= y; hv[0] <= 0;
					if (y == 721) av_sync <= 0;
				end
			for (y = 0; y < 720; y = y + 1)
				for (x = 0; x < 1650; x = x + 1) begin
					@(posedge clk_av);
					av_x <= x; av_y <= y;
					hv[0] <= (x < 1280) && checking;
				end
		end
		if (checking) screens = screens + 1;
		if (screens >= SCREENS) begin
			repeat (20) @(posedge clk_av);
			$display("gb_fb %0dx%0d%s%s ce/%0d %s%s: %0d screens, %0d pixels, %0d errors (%0d black), sram %0d errors, %0d lines late, overflow %0d, geometry %h",
			         W, H, DBL ? " doubled" : "", LACE ? " interlaced" : "", CE, HDMI ? "HDMI" : "panel",
			         SAFE ? " safe" : "", screens, checked, errors, black_in, sram_err, late, ovf, geom);
			if (errors == 0 && sram_err == 0 && !ovf) $display("PASS"); else $display("FAIL");
			$finish;
		end
	end
end

`ifdef GLS
// netlist probe: the fetch logic at the first pixels of a few columns
wire [9:0] g_need = {dut.\need_reg_n_0_[9] , dut.\need_reg_n_0_[8] , dut.\need_reg_n_0_[7] , dut.\need_reg_n_0_[6] ,
                     dut.\need_reg_n_0_[5] , dut.\need_reg_n_0_[4] , dut.\need_reg_n_0_[3] , dut.\need_reg_n_0_[2] ,
                     dut.\need_reg_n_0_[1] , dut.\need_reg_n_0_[0] };
always @(posedge clk_av) if ($test$plusargs("probe") && av_y < 3 && av_x >= 38 && av_x <= 48 && screens == 1)
	$display("probe x %0d y %0d: need %0d k_cur %0d k_ok1 %b k_ok %b f_next %0d q_busy %b calc %b%b%b%b", av_x, av_y,
	         g_need, dut.k_cur_reg__0, dut.k_ok1, dut.k_ok_reg__0, dut.f_next, dut.q_busy,
	         dut.\calc_reg_n_0_[3] , dut.\calc_reg_n_0_[2] , dut.\calc_reg_n_0_[1] , dut.\calc_reg_n_0_[0] );
`endif
// the colour 12 clocks after the pixel was named
`ifndef GLS
reg [15:0] late_d = 0;
always @(posedge clk_av) begin
	late_d <= late;
	if (late != late_d && late < 8 && $test$plusargs("dbg"))
		$display("late at %0t: x %0d y %0d need %0d f_next %0d rdy %b q_busy %b tags %0d %0d %0d %0d c_s %0d c_p %0d o_s %0d e_s %0d",
		         $time, av_x, av_y, dut.need, dut.f_next, dut.rdy, dut.q_busy, dut.tag0, dut.tag1, dut.tag2, dut.tag3,
		         dut.c_s, dut.c_p, dut.o_s, dut.e_s);
end
`endif
always @(posedge clk_av) begin
	hx[0] <= av_x; hy[0] <= av_y;
	for (int i = 1; i < 12; i++) begin hx[i] <= hx[i-1]; hy[i] <= hy[i-1]; hv[i] <= hv[i-1]; end
	if (hv[11]) check(hx[11], hy[11]);
end

endmodule
