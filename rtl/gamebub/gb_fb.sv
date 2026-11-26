// Game Bub Falcon: the picture. Videl's pixels are captured at the
// Falcon's own resolution, kept by the core in the board's SRAM and block
// RAM, and shown through the framework's external picture (patches/framework
// 0003, 0005: ownFrames) on the handheld's panel and on HDMI.
//
// Capture (clk_sys). A pixel is taken at Videl's ce_pix while de_tb is high:
// de_tb is Videl's display enable for one copy of every source line (the
// second copy of a doubled line), so a 320 x 240 VGA screen, which Videl
// sends as 480 lines, is kept as 240. Interlaced fields (Videl VMD bit 1)
// are woven: line n of field f is line 2n + f. A frame ends where vblank
// rises; its width (the longest line) and height are measured then and are
// the layout of the next frame (a frame is stored line after line, a line
// `stride` pixels apart): after a mode change one frame is stored in the old
// layout. Pixels are kept as RGB 5:6:5 (Videl's colours are 6 bit, the
// Falcon's true colour 5:6:5).
//
// Store. q = 0..307,199: q < 262,144 in the SRAM word q, the rest in block
// RAM (45,056 words: three memories of 32,768, 8,192 and 4,096).
//   - A frame of at most 153,600 pixels (320 x 240, 320 x 480, 640 x 240,
//     384 x 240 ...), not interlaced: two frames, at q = 0 and 153,600; the
//     framework decides which one a frame goes to and whether it is thrown
//     away because the panel shows that frame (wr_frame, wr_drop), and which
//     the panel shows (av_frame). No seams.
//   - Bigger (640 x 400, 640 x 480, up to 307,200 pixels) or interlaced: one
//     frame at q = 0, written while it is shown (a seam where the picture
//     moves while it is scanned).
//
// Show (clk_av, the pixel clock of the screen shown). The framework names a
// pixel every clock (av_x, av_y) and takes its colour 12 clocks later. The
// picture is scaled at every screen frame (av_sync) from the geometry of
// the frame shown:
//   - panel, the 720 x 480 the framework gives a picture on rev 4: whole
//     factors sx = 800 / W (at most 4), sy = 480 / H (at most 4), neither
//     more than twice the other (320 x 200 shows as 640 x 400, 640 x 200 as
//     640 x 400, 320 x 480 as 640 x 480), centred; a picture wider than 720
//     (384 x 240 overscan at 768) loses its edges evenly;
//   - HDMI, 1280 x 720: the panel's picture made 1.5 times bigger
//     (nearest pixel), centred.
// A screen position p on an axis shows source pixel (p - O) * N / D (N 1 or
// 2, D up to 12), computed as (p - O) * N * ceil(65536 / D) >> 16, exact for
// every p of the screen.
// The panel is scanned in columns of the landscape picture, HDMI in lines:
// the source columns (panel) or lines (HDMI) are read ahead into four line
// buffers (index k in buffer k mod 4): at av_sync the first four are
// fetched, and source line k + 3 once line k is being shown.
//
// The SRAM (clk_mem, 3 x clk_sys of the same MMCM) as the Game Bub Minimig
// core drives it (rtl/gamebub/falcon.xdc times it): every pin from a
// register in its I/O block, WE from an ODDR, the data bus direction from
// one register; a word takes T clocks (sram_safe: 3, else 2):
//   - write: address, data and byte enables for T clocks, WE low from the
//     middle of the first clock to the middle of the second (T = 2) or the
//     end of the second (T = 3);
//   - read: the address with OE low for T clocks, the data taken at the
//     edge that ends them;
//   - one idle clock (OE high, the FPGA not driving) where the bus turns.
// Pixels in the block RAM part take one clock and leave the SRAM's pins
// as they are. The captured
// pixels wait in a queue of 1024 (block RAM written in clk_sys, read in
// clk_mem); reads go on until 8 are waiting, then the queue is written until
// it is empty or a scan line's read is due.
//
// SPDX-License-Identifier: GPL-2.0-or-later

module gb_fb
(
	// Videl (clk_sys)
	input             clk_sys,
	input             reset,
	input             ce_pix,
	input             de_tb,
	input             vblank,
	input             field,
	input             lace,
	input       [7:0] r,
	input       [7:0] g,
	input       [7:0] b,
	input             wr_frame,      // the framework: the frame these pixels belong to
	input             wr_drop,       // and whether they are thrown away
	output reg        fw_de = 1'b0,  // the stream the framework counts
	output reg        fw_hblank = 1'b1,
	output reg        fw_vblank = 1'b1,

	// the SRAM (clk_mem)
	input             clk_mem,
	input             reset_mem,
	input             sram_safe,     // three clocks a word (clk_sys, changes rarely)
	output            sram_ceN,
	output            sram_weN,
	output            sram_oeN,
	output      [1:0] sram_writeMaskN,
	output     [17:0] sram_address,
	input      [15:0] sram_dataIn,
	output     [15:0] sram_dataOut,
	output            sram_dataDir,

	// the framework's external picture (clk_av)
	input             clk_av,
	input             av_hdmi,
	input             av_sync,
	input             av_frame,
	input      [10:0] av_x,
	input       [9:0] av_y,
	output reg [23:0] av_color = 24'd0,

	// observation
	output reg [31:0] dbg_geom = 32'd0,      // clk_sys: the last frame: lace 31, double 30, height 25:16, width 9:0
	output reg [15:0] dbg_lines = 16'd0,     // clk_mem: source lines fetched
	output reg [15:0] dbg_late = 16'd0,      // clk_av: scan lines shown before their line was fetched
	output reg        dbg_overflow = 1'b0    // clk_sys: a pixel found the queue full
);

localparam [18:0] CAP   = 19'd307200;
localparam [18:0] HALF  = 19'd153600;
localparam [18:0] SRAMW = 19'd262144;
localparam [9:0]  WMAX  = 10'd800;

// ===========================================================================
// capture (clk_sys)
// ===========================================================================
reg        de_d = 1'b0, vb_d = 1'b1;
reg  [9:0] x = 10'd0;             // pixel of the line
reg  [9:0] n = 10'd0;             // lines of the field
reg  [9:0] w_max = 10'd0;         // longest line of the frame
reg        f_lace = 1'b0, f_field = 1'b0;
// the layout of the frame being written
reg  [9:0] l_stride = 10'd320;
reg        l_dbl = 1'b1;
reg        l_lace = 1'b0;
reg [18:0] row = 19'd0;           // the line's first pixel (frame relative)
reg        lin = 1'b0;            // pixels of a line seen
// the frames' geometry: {single, stride, W, H}
reg  [9:0] g_w [0:1], g_h [0:1], g_s [0:1];
reg        g_single = 1'b0;
reg        pub_tgl = 1'b0;

// queue (written here, read in clk_mem)
reg [34:0] wq [0:1023];
reg [10:0] wq_wp = 11'd0;
wire [10:0] wq_rp;                // clk_mem
wire [10:0] wq_level_s = wq_wp - wq_rp;

wire       take = ce_pix && de_tb && !vblank;
wire [18:0] px_q   = row + {9'd0, x};
wire [18:0] base   = (l_dbl && wr_frame) ? HALF : 19'd0;
wire [18:0] limit  = l_dbl ? HALF : CAP;
wire [15:0] rgb565 = {r[7:3], g[7:2], b[7:3]};
wire        keep   = (x < l_stride) && (px_q < limit) && !(l_dbl && wr_drop);

// a frame of at most HALF pixels, not interlaced, is double buffered
wire [19:0] area = w_max * (f_lace ? {n, 1'b0} : {1'b0, n});

always @(posedge clk_sys) begin
	de_d <= de_tb;
	vb_d <= vblank;
	fw_de <= take;
	fw_hblank <= !de_tb;
	fw_vblank <= vblank;
	if (reset) begin
		x <= 10'd0; n <= 10'd0; w_max <= 10'd0; lin <= 1'b0; row <= 19'd0;
		wq_wp <= 11'd0;
		l_stride <= 10'd320; l_dbl <= 1'b1; l_lace <= 1'b0;
		g_single <= 1'b0;
	end
	else begin
		if (take) begin
			if (x != 10'h3FF) x <= x + 10'd1;
			lin <= 1'b1;
			if (keep) begin
				if (wq_level_s[10]) dbg_overflow <= 1'b1;
				else begin
					wq[wq_wp[9:0]] <= {base + px_q, rgb565};
					wq_wp <= wq_wp + 11'd1;
				end
			end
		end
		// a line ends
		if (de_d && !de_tb && lin) begin
			lin <= 1'b0;
			x   <= 10'd0;
			if (x > w_max) w_max <= x;
			n   <= n + 10'd1;
			row <= row + (l_lace ? {8'd0, l_stride, 1'b0} : {9'd0, l_stride});
		end
		// the first line of a field
		if (!vblank && vb_d) begin
			f_lace  <= lace;
			f_field <= field;
			row     <= (l_lace && field) ? {9'd0, l_stride} : 19'd0;
		end
		// the frame ends: its geometry, the next frame's layout
		if (vblank && !vb_d) begin
			x <= 10'd0; lin <= 1'b0;
			if (n != 10'd0) begin
				if (l_dbl) begin
					g_w[wr_frame] <= (w_max > l_stride) ? l_stride : w_max;
					g_h[wr_frame] <= f_lace ? {n[8:0], 1'b0} : n;
					g_s[wr_frame] <= l_stride;
				end
				else begin
					g_w[0] <= (w_max > l_stride) ? l_stride : w_max;
					g_h[0] <= f_lace ? {n[8:0], 1'b0} : n;
					g_s[0] <= l_stride;
				end
				g_single <= !l_dbl;
				pub_tgl  <= ~pub_tgl;
				dbg_geom <= {f_lace, l_dbl, 4'd0, (f_lace ? {n[8:0], 1'b0} : n), 6'd0, w_max};
				// the next frame
				l_stride <= (w_max > WMAX) ? WMAX : (w_max == 10'd0) ? 10'd1 : w_max;
				l_lace   <= f_lace;
				l_dbl    <= !f_lace && (area <= {1'b0, HALF});
			end
			n <= 10'd0;
			w_max <= 10'd0;
		end
	end
end

// ===========================================================================
// the screen's side (clk_av): geometry, scaling, fetch requests, pixels
// ===========================================================================
(* ASYNC_REG = "TRUE" *) reg [2:0] pub_s = 3'd0;
reg  [9:0] a_w [0:1], a_h [0:1], a_s [0:1];
reg        a_single = 1'b0;
(* ASYNC_REG = "TRUE" *) reg [1:0] safe_s = 2'b00;

// the frame shown and its scaling
reg        sync_d = 1'b0;
reg        v_hdmi = 1'b0, v_slot = 1'b0, v_ok = 1'b0;
reg  [9:0] v_w = 10'd0, v_h = 10'd0, v_s = 10'd1;
reg  [2:0] v_sx = 3'd1, v_sy = 3'd1;
reg  [3:0] calc = 4'd0;           // steps of the computation after av_sync
// per axis: scan (s: panel column / HDMI line) and along (p)
reg signed [12:0] o_s, o_p;       // first screen position of the picture (negative: cut)
reg [11:0] e_s, e_p;              // its extent
reg  [3:0] d_s, d_p;              // denominators
reg        n2;                    // N = 2 (HDMI)
reg [16:0] r_s, r_p;              // ceil(65536 / D)
reg  [9:0] c_s, c_p;              // source lines (scan axis), pixels of a line (along)

function automatic [16:0] recip(input [3:0] d);
	case (d)
		4'd1: recip = 17'd65536; 4'd2: recip = 17'd32768; 4'd3: recip = 17'd21846;
		4'd4: recip = 17'd16384; 4'd5: recip = 17'd13108; 4'd6: recip = 17'd10923;
		4'd7: recip = 17'd9363;  4'd8: recip = 17'd8192;  4'd9: recip = 17'd7282;
		4'd10: recip = 17'd6554; 4'd11: recip = 17'd5958; default: recip = 17'd5462;
	endcase
endfunction
function automatic [2:0] fit(input [9:0] v, input [9:0] t2, input [9:0] t3, input [9:0] t4);
	fit = (v <= t4) ? 3'd4 : (v <= t3) ? 3'd3 : (v <= t2) ? 3'd2 : 3'd1;
endfunction

// fetch requests to clk_mem: one at a time
reg        q_tgl = 1'b0;
(* dont_touch = "true" *) reg [18:0] q_a = 19'd0;      // first pixel
(* dont_touch = "true" *) reg  [9:0] q_step = 10'd1;   // pixels between two of the line
(* dont_touch = "true" *) reg  [9:0] q_cnt = 10'd0;    // pixels
(* dont_touch = "true" *) reg  [1:0] q_slot = 2'd0;
wire       m_done_tgl;            // from clk_mem
(* ASYNC_REG = "TRUE" *) reg [2:0] done_s = 3'd0;
reg        q_busy = 1'b0;
reg  [9:0] f_next = 10'd0;        // the next source line to fetch
// the source line in each buffer: four registers, written and read with
// constant indices. (As `reg [9:0] tag [0:3]` written at tag[f_next[1:0]],
// Vivado 2018.3 made a distributed RAM of it addressed by all of f_next on
// the write side and by the buffer number on the read side: lines from the
// fifth on were never found ready, and the panel showed four columns.)
reg  [9:0] tag0 = 10'd0, tag1 = 10'd0, tag2 = 10'd0, tag3 = 10'd0;
function automatic [9:0] tag_of(input [1:0] i, input [9:0] t0, input [9:0] t1, input [9:0] t2, input [9:0] t3);
	case (i)
		2'd0: tag_of = t0;
		2'd1: tag_of = t1;
		2'd2: tag_of = t2;
		default: tag_of = t3;
	endcase
endfunction
reg  [3:0] rdy = 4'd0;
reg [19:0] f_base;                // f_next's first pixel (relative to the frame)

// scan line shown: its source index
reg [10:0] sx1 = 11'd0;
reg  [9:0] sy1 = 10'd0;
reg [11:0] ds;                    // scan position relative to the picture
reg        ds_in = 1'b0;
reg [28:0] k_prod;
reg  [9:0] k_cur = 10'd0;
reg        k_ok = 1'b0, k_ok1 = 1'b0;
reg  [9:0] need = 10'd0;          // highest source line shown so far

wire [11:0] scan_pos  = v_hdmi ? {2'd0, sy1} : {1'b0, sx1};
wire [11:0] along_pos = v_hdmi ? {1'b0, sx1} : {2'd0, sy1};

always @(posedge clk_av) begin
	pub_s  <= {pub_s[1:0], pub_tgl};
	safe_s <= {safe_s[0], sram_safe};
	done_s <= {done_s[1:0], m_done_tgl};
	if (pub_s[2] != pub_s[1]) begin
		a_w[0] <= g_w[0]; a_h[0] <= g_h[0]; a_s[0] <= g_s[0];
		a_w[1] <= g_w[1]; a_h[1] <= g_h[1]; a_s[1] <= g_s[1];
		a_single <= g_single;
	end
	sync_d <= av_sync;
	sx1 <= av_x;
	sy1 <= av_y;

	// a screen frame begins: take the frame to show, compute the scaling
	if (av_sync && !sync_d) begin
		v_hdmi <= av_hdmi;
		v_slot <= a_single ? 1'b0 : av_frame;
		calc   <= 4'd1;
		v_ok   <= 1'b0;
		rdy    <= 4'd0;
		f_next <= 10'd0;
		need   <= 10'd0;
	end
	else case (calc)
		4'd1: begin
			v_w <= a_w[v_slot]; v_h <= a_h[v_slot]; v_s <= a_s[v_slot];
			calc <= 4'd2;
		end
		4'd2: begin
			v_sx <= fit(v_w, 10'd400, 10'd266, 10'd200);
			v_sy <= fit(v_h, 10'd240, 10'd160, 10'd120);
			calc <= 4'd3;
		end
		4'd3: begin
			// neither factor more than twice the other (compared at 4 bits: a
			// factor of 4 is 3'b100, and its two low bits alone are 0, which
			// clamped the other factor to 0: pictures up to 200 wide, or up to
			// 120 high, were not shown. Where a factor is clamped the other is
			// 1, so twice it fits in 3 bits.)
			if ({1'b0, v_sx} > {v_sy, 1'b0}) v_sx <= {v_sy[1:0], 1'b0};
			if ({1'b0, v_sy} > {v_sx, 1'b0}) v_sy <= {v_sx[1:0], 1'b0};
			calc <= 4'd4;
		end
		4'd4: begin
			// D: the panel's factor, or 3 x it over N = 2 on HDMI
			n2  <= v_hdmi;
			d_s <= v_hdmi ? 4'(3 * v_sy) : {1'b0, v_sx};
			d_p <= v_hdmi ? 4'(3 * v_sx) : {1'b0, v_sy};
			c_s <= v_hdmi ? v_h : v_w;
			c_p <= v_hdmi ? v_w : v_h;
			calc <= 4'd5;
		end
		4'd5: begin
			r_s <= recip(d_s);
			r_p <= recip(d_p);
			// extents on the screen: source size x D / N
			e_s <= n2 ? 12'((c_s * d_s + 1) >> 1) : 12'(c_s * d_s);
			e_p <= n2 ? 12'((c_p * d_p + 1) >> 1) : 12'(c_p * d_p);
			calc <= 4'd6;
		end
		4'd6: begin
			// centred: panel 720 columns x 480 rows; HDMI 1280 x 720 lines
			o_s <= (v_hdmi ? 13'sd720 : 13'sd720) - $signed({1'b0, e_s}) >>> 1;
			o_p <= (v_hdmi ? 13'sd1280 : 13'sd480) - $signed({1'b0, e_p}) >>> 1;
			v_ok <= (v_w != 10'd0) && (v_h != 10'd0) && (e_s <= (v_hdmi ? 12'd720 : 12'd800)) &&
			        (e_p <= (v_hdmi ? 12'd1280 : 12'd480));
			calc <= 4'd7;
		end
		4'd7: begin
			// a picture cut at its edges: the first source line shown
			k_prod <= (o_s < 0) ? (n2 ? {12'(-o_s), 1'b0} : {1'b0, 12'(-o_s)}) * r_s : 29'd0;
			calc <= 4'd8;
		end
		4'd8: begin
			need   <= k_prod[25:16];
			f_next <= k_prod[25:16];
			calc   <= 4'd9;
		end
		4'd9: calc <= 4'd0;   // f_base (a register) follows f_next
		default: ;
	endcase

	// the scan line shown: its source line
	ds    <= 12'($signed({1'b0, scan_pos}) - o_s);
	// (only pixels of the screen: outside them x and y mean nothing)
	ds_in <= ($signed({1'b0, scan_pos}) >= o_s) && ($signed({1'b0, scan_pos}) < o_s + $signed({1'b0, e_s})) &&
	         (v_hdmi ? (sx1 < 11'd1280) : (sy1 < 10'd480 && sx1 < 11'd720));
	if (calc != 4'd7) k_prod <= (n2 ? {ds, 1'b0} : {1'b0, ds}) * r_s;
	k_ok1 <= ds_in && v_ok && calc == 4'd0;
	k_cur <= k_prod[25:16];
	k_ok  <= k_ok1;
	// the source line shown advances one at a time
	if (k_ok && k_cur == need + 10'd1 && k_cur < c_s && calc == 4'd0) need <= k_cur;

	// fetch: the next source line into its buffer once a buffer is free
	if (done_s[2] != done_s[1]) begin
		q_busy <= 1'b0;
		rdy[q_slot] <= 1'b1;
	end
	f_base <= v_hdmi ? f_next * v_s : {10'd0, f_next};
	if (!q_busy && v_ok && calc == 4'd0 && !(av_sync && !sync_d) &&
	    f_next < c_s && f_next <= need + 10'd3 && done_s[2] == done_s[1]) begin
		q_a    <= (v_slot ? HALF : 19'd0) + f_base[18:0];
		q_step <= v_hdmi ? 10'd1 : v_s;
		q_cnt  <= c_p;
		q_slot <= f_next[1:0];
		case (f_next[1:0])
			2'd0: tag0 <= f_next;
			2'd1: tag1 <= f_next;
			2'd2: tag2 <= f_next;
			default: tag3 <= f_next;
		endcase
		rdy[f_next[1:0]] <= 1'b0;
		q_tgl  <= ~q_tgl;
		q_busy <= 1'b1;
		f_next <= f_next + 10'd1;
	end
end

// the pixels: 12 registers from av_x / av_y to av_color (sx1 / sy1 the first)
reg [11:0] p1_d;
reg        p1_in;
reg [28:0] p2_prod;
reg        p2_in;
reg  [9:0] p3_j;
reg        p3_in, p3_k_ok;
reg  [9:0] p3_k;
reg [11:0] p4_a;
reg        p4_ok;
reg [15:0] lbuf [0:4095];
reg [15:0] p5_q, p6_q;
reg        p5_ok, p6_ok;
reg [23:0] p_c [7:10];
always @(posedge clk_av) begin
	// 1: position on the along axis (the scan line's k follows with the
	// same latency: ds was taken from the same av_x / av_y)
	p1_d  <= 12'($signed({1'b0, along_pos}) - o_p);
	p1_in <= ($signed({1'b0, along_pos}) >= o_p) && ($signed({1'b0, along_pos}) < o_p + $signed({1'b0, e_p}));
	// 2: times N / D
	p2_prod <= (n2 ? {p1_d, 1'b0} : {1'b0, p1_d}) * r_p;
	p2_in   <= p1_in;
	// 3: the source pixel; the scan line's source line (k_cur, k_ok)
	p3_j    <= p2_prod[25:16];
	p3_in   <= p2_in;
	p3_k    <= k_prod[25:16];
	p3_k_ok <= k_ok1;
	// 4: the buffer
	p4_a  <= {p3_k[1:0], p3_j};
	p4_ok <= p3_in && p3_k_ok && rdy[p3_k[1:0]] && tag_of(p3_k[1:0], tag0, tag1, tag2, tag3) == p3_k && p3_j < c_p;
	if (p3_in && p3_k_ok && !(rdy[p3_k[1:0]] && tag_of(p3_k[1:0], tag0, tag1, tag2, tag3) == p3_k) && p3_j == 10'd0 && ~&dbg_late)
		dbg_late <= dbg_late + 16'd1;
	// 5, 6: read
	p5_q  <= lbuf[p4_a];
	p5_ok <= p4_ok;
	p6_q  <= p5_q;
	p6_ok <= p5_ok;
	p_c[7] <= !p6_ok ? 24'd0 :
	          {p6_q[15:11], p6_q[15:13], p6_q[10:5], p6_q[10:9], p6_q[4:0], p6_q[4:2]};
	for (int i = 8; i < 11; i++) p_c[i] <= p_c[i - 1];
	av_color <= p_c[10];
end

// ===========================================================================
// the memories and the SRAM pins (clk_mem)
// ===========================================================================
// queue read side
reg [10:0] m_rp = 11'd0;
assign wq_rp = m_rp;
reg  [10:0] wp_m = 11'd0;          // the write pointer a clock later: an entry is
always @(posedge clk_mem) wp_m <= wq_wp;   // read only after the clock it was written in
wire [10:0] m_level = wp_m - m_rp;
reg [34:0] wq_q;
reg        wq_q_v = 1'b0;          // wq_q holds entry m_rp (read a clock after m_rp changes)
always @(posedge clk_mem) wq_q <= wq[m_rp[9:0]];

// block RAM part: q - 262,144 in 0..45,055
reg [15:0] bm0 [0:32767];
reg [15:0] bm1 [0:8191];
reg [15:0] bm2 [0:4095];
reg        bm_we = 1'b0;
reg [15:0] bm_a;                  // 0..45,055
reg [15:0] bm_wd;
reg [15:0] bm0_q, bm1_q, bm2_q;
reg [15:0] bm_a1;
reg        bm0_we1 = 1'b0, bm1_we1 = 1'b0, bm2_we1 = 1'b0;
reg [15:0] bm_wd1;
always @(posedge clk_mem) begin
	bm_a1   <= bm_a;
	bm_wd1  <= bm_wd;
	bm0_we1 <= bm_we && !bm_a[15];
	bm1_we1 <= bm_we && bm_a[15] && !bm_a[13];
	bm2_we1 <= bm_we && bm_a[15] && bm_a[13];
end
always @(posedge clk_mem) begin
	if (bm0_we1) bm0[bm_a1[14:0]] <= bm_wd1;
	bm0_q <= bm0[bm_a1[14:0]];
end
always @(posedge clk_mem) begin
	if (bm1_we1) bm1[bm_a1[12:0]] <= bm_wd1;
	bm1_q <= bm1[bm_a1[12:0]];
end
always @(posedge clk_mem) begin
	if (bm2_we1) bm2[bm_a1[11:0]] <= bm_wd1;
	bm2_q <= bm2[bm_a1[11:0]];
end
reg [15:0] bm_a2;
always @(posedge clk_mem) bm_a2 <= bm_a1;
wire [15:0] bm_q = !bm_a2[15] ? bm0_q : !bm_a2[13] ? bm1_q : bm2_q;

// line buffers (written here, read in clk_av)
reg        lb_we = 1'b0;
reg [11:0] lb_wa;
reg [15:0] lb_wd;
always @(posedge clk_mem) if (lb_we) lbuf[lb_wa] <= lb_wd;

// SRAM pins: plan registers, then the registers in the I/O blocks
reg [17:0] p_addr = 18'd0;
reg [15:0] p_data = 16'd0;
reg  [1:0] p_mask = 2'b11;
reg        p_oe_n = 1'b1, p_dir = 1'b0, p_we1 = 1'b1, p_we2 = 1'b1;
(* IOB = "TRUE" *) reg [17:0] o_addr = 18'd0;
(* IOB = "TRUE" *) reg [15:0] o_data = 16'd0;
(* IOB = "TRUE" *) reg  [1:0] o_mask = 2'b11;
(* IOB = "TRUE" *) reg        o_oe_n = 1'b1;
(* IOB = "TRUE" *) reg [15:0] i_data = 16'd0;
reg        o_dir = 1'b0;
always @(posedge clk_mem) begin
	o_addr <= p_addr;
	o_data <= p_data;
	o_mask <= p_mask;
	o_oe_n <= p_oe_n;
	o_dir  <= p_dir;
	i_data <= sram_dataIn;
end
ODDR #(
	.DDR_CLK_EDGE("SAME_EDGE"),
	.INIT(1'b1),
	.SRTYPE("SYNC")
) we_oddr (
	.Q (sram_weN),
	.C (clk_mem),
	.CE(1'b1),
	.D1(p_we1),
	.D2(p_we2),
	.R (1'b0),
	.S (1'b0)
);
assign sram_ceN        = 1'b0;
assign sram_oeN        = o_oe_n;
assign sram_writeMaskN = o_mask;
assign sram_address    = o_addr;
assign sram_dataOut    = o_data;
assign sram_dataDir    = o_dir;

// the fetch request
(* ASYNC_REG = "TRUE" *) reg [2:0] r_ts = 3'd0;
reg        m_done = 1'b0;
assign     m_done_tgl = m_done;
reg        j_act = 1'b0;          // a line to read
reg [18:0] j_a;
reg  [9:0] j_step;
reg  [9:0] j_left;
reg  [9:0] j_i;
reg  [1:0] j_slot;
reg  [6:0] j_flight = 7'd0;       // reads on their way (done when 0 and none left)
(* ASYNC_REG = "TRUE" *) reg [1:0] safe_m = 2'b00;
wire       t3 = safe_m[1];

localparam [1:0] S_IDLE = 2'd0, S_GAP = 2'd1, S_OP = 2'd2, S_BOP = 2'd3;
reg  [1:0] st = S_IDLE;
reg  [1:0] ph = 2'd0;
reg        cur_wr = 1'b0;
reg        last_we = 1'b0;
reg        draining = 1'b0;
wire [1:0] ph_last = t3 ? 2'd2 : 2'd1;
wire       boundary = (st != S_OP) || (ph == ph_last);
wire       q_have = (m_level != 11'd0) && wq_q_v;
wire       want_wr = q_have && (m_level >= 11'd8 || draining || !(j_act && j_left != 10'd0));
wire       want_rd = j_act && (j_left != 10'd0) && !want_wr;
// the next word is in the block RAM part: one clock, the SRAM's bus untouched
wire       next_bm = want_wr ? !(wq_q[34:16] < SRAMW) : !(j_a < SRAMW);

// a read's way to the line buffer: due[k] is high in the k-th clock after
// the one it starts at (E0). The address is at the pins from E1 for T
// clocks; i_data takes the word at E1 + T and holds it for a clock: it goes
// to the line buffer at E2 + T (due[T + 1]). The block RAM's word (bm_a,
// bm_a1, the memory, bm_a2's select) is held at E3 (due[2]).
reg  [5:0] due = 6'd0;
reg [12:0] rtag [0:5];            // {in block RAM, slot, index}
reg [15:0] hold_bm, hold_bm2;

always @(posedge clk_mem) begin
	reg start_rd;
	start_rd = 1'b0;
	safe_m <= {safe_m[0], sram_safe};
	bm_we <= 1'b0;
	lb_we <= 1'b0;
	wq_q_v <= 1'b1;

	if (st == S_OP && ph == 2'd0) begin
		ph <= 2'd1;
		if (cur_wr) begin p_we1 <= 1'b0; p_we2 <= t3 ? 1'b0 : 1'b1; end   // T=2: up in the middle of the second
	end
	else if (st == S_OP && ph == 2'd1 && t3) begin
		ph <= 2'd2;
		p_we1 <= 1'b1; p_we2 <= 1'b1;
	end
	else if (boundary) begin
		p_we1 <= 1'b1; p_we2 <= 1'b1;
		if (!want_wr && !want_rd) st <= S_IDLE;
		else if (next_bm) begin
			// a word of the block RAM part
			st <= S_BOP;
			if (want_wr) begin
				m_rp   <= m_rp + 11'd1;
				wq_q_v <= 1'b0;
				bm_a   <= 16'(wq_q[34:16] - SRAMW);
				bm_wd  <= wq_q[15:0];
				bm_we  <= 1'b1;
			end
			else begin
				bm_a   <= 16'(j_a - SRAMW);
				start_rd = 1'b1;
				rtag[0] <= {1'b1, j_slot, j_i};
				j_a    <= j_a + {9'd0, j_step};
				j_i    <= j_i + 10'd1;
				j_left <= j_left - 10'd1;
			end
		end
		else if (st != S_GAP && want_wr != last_we) begin
			st     <= S_GAP;
			p_dir  <= 1'b0;
			p_oe_n <= 1'b1;
			p_mask <= 2'b11;
		end
		else begin
			st      <= S_OP;
			ph      <= 2'd0;
			last_we <= want_wr;
			if (want_wr) begin
				// the queue's head (wq_q) is taken; the next is read a clock later
				m_rp   <= m_rp + 11'd1;
				wq_q_v <= 1'b0;
				cur_wr <= (wq_q[34:16] < SRAMW);
				p_addr <= wq_q[33:16];
				p_data <= wq_q[15:0];
				p_mask <= (wq_q[34:16] < SRAMW) ? 2'b00 : 2'b11;
				p_dir  <= 1'b1;
				p_oe_n <= 1'b1;
				p_we1  <= 1'b1;
				p_we2  <= !(wq_q[34:16] < SRAMW);     // falls in the middle of the first clock
				bm_a   <= 16'(wq_q[34:16] - SRAMW);
				bm_wd  <= wq_q[15:0];
				bm_we  <= !(wq_q[34:16] < SRAMW);
			end
			else begin
				cur_wr <= 1'b0;
				p_addr <= j_a[17:0];
				p_mask <= 2'b00;
				p_dir  <= 1'b0;
				p_oe_n <= 1'b0;
				bm_a   <= 16'(j_a - SRAMW);
				start_rd = 1'b1;
				rtag[0] <= {!(j_a < SRAMW), j_slot, j_i};
				j_a    <= j_a + {9'd0, j_step};
				j_i    <= j_i + 10'd1;
				j_left <= j_left - 10'd1;
			end
		end
	end
	if (m_level >= 11'd8) draining <= 1'b1;
	else if (m_level == 11'd0) draining <= 1'b0;

	// reads on their way
	due <= {due[4:0], start_rd};
	for (int i = 1; i < 6; i++) rtag[i] <= rtag[i - 1];
	if (due[2]) hold_bm <= bm_q;
	if (due[3]) hold_bm2 <= hold_bm;
	if (t3 ? due[4] : due[3]) begin
		lb_we <= 1'b1;
		lb_wa <= t3 ? rtag[4][11:0] : rtag[3][11:0];
		lb_wd <= t3 ? (rtag[4][12] ? hold_bm2 : i_data) : (rtag[3][12] ? hold_bm : i_data);
	end
	j_flight <= j_flight + (start_rd ? 7'd1 : 7'd0) - ((t3 ? due[4] : due[3]) ? 7'd1 : 7'd0);

	// a line read completely
	if (j_act && j_left == 10'd0 && j_flight == 7'd0 && !start_rd && due == 6'd0) begin
		j_act   <= 1'b0;
		m_done  <= ~m_done;
		dbg_lines <= dbg_lines + 16'd1;
	end
	// a new request
	r_ts <= {r_ts[1:0], q_tgl};
	if (r_ts[2] != r_ts[1]) begin
		j_act  <= 1'b1;
		j_a    <= q_a;
		j_step <= q_step;
		j_left <= q_cnt;
		j_i    <= 10'd0;
		j_slot <= q_slot;
	end

	if (reset_mem) begin
		st <= S_IDLE; p_oe_n <= 1'b1; p_dir <= 1'b0; p_mask <= 2'b11; p_we1 <= 1'b1; p_we2 <= 1'b1;
		last_we <= 1'b0; due <= 6'd0; j_flight <= 7'd0; draining <= 1'b0;
		m_rp <= wq_wp;
		j_act <= 1'b0;
	end
end

endmodule
