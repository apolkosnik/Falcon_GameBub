// Game Bub Falcon: Game Bub controllers, and the dock's mouse and keyboard
// (written by the firmware fork, gb_host), as MiSTer's hps_io gives them to
// falcon_system: joysticks (MiSTer bit order), PS/2 mouse packets and PS/2
// set 2 key events, which falcon_ikbd turns into the IKBD's.
//
// Slot 0 (the handheld's buttons, or the first dock controller):
//   D-pad, left stick  the joystick in ST port 1 (the games' port)
//   A                  its fire button
//   B                  the right mouse button
//   R                  the left mouse button
//   right stick        moves the mouse
//   L (held)           the D-pad moves the mouse, A and B are its left and
//                      right buttons (the joystick is let go)
//   X, Y, Start,       keys (USB HID usages from the settings; defaults
//   Select             Space, Return, Help (F11), Esc)
// Slot 1 (a second dock controller): D-pad, left stick and A the joystick
//   in ST port 0 (the mouse port; the IKBD takes it when the program asks).
// Host mouse: moves the mouse, its buttons are the mouse's.
// Host keyboard: every key, translated from its USB HID usage to PS/2 set 2
//   (and by falcon_ikbd's keymap to the ST's: F11 Help, F12 Undo, Page Up /
//   Down the keypad's ( and )).
//
// The mouse is sent as PS/2 packets (falcon_ikbd's ps2_mouse: bit 24
// toggles, 23:16 dy up positive, 15:8 dx, 7:0 buttons and signs) every 10 ms
// while it moves or its buttons change; keys from a queue of 16, one every
// 2 ms.
//
// SPDX-License-Identifier: GPL-2.0-or-later

module gb_input
#(
	parameter integer CLK_HZ = 31979167
)
(
	input             clk,
	input             reset,

	input             btn_a, btn_b, btn_x, btn_y,
	input             btn_up, btn_down, btn_left, btn_right,
	input             btn_l, btn_r, btn_start, btn_select,
	input signed [7:0] stick_lx, stick_ly,
	input signed [7:0] stick_rx, stick_ry,

	input             p1_active,
	input             p1_a,
	input             p1_up, p1_down, p1_left, p1_right,
	input signed [7:0] p1_lx, p1_ly,

	input       [7:0] key_x,
	input       [7:0] key_y,
	input       [7:0] key_start,
	input       [7:0] key_select,
	input       [1:0] mouse_speed,   // 0 slow, 1 normal, 2 fast, 3 faster

	input             hmouse_valid,
	input      [15:0] hmouse_dx,     // right positive
	input      [15:0] hmouse_dy,     // down positive
	input       [2:0] hmouse_btn,    // {middle, right, left}
	input             hkey_valid,
	input       [7:0] hkey_usage,
	input             hkey_down,

	output     [31:0] joy0,          // ST port 1
	output     [31:0] joy1,          // ST port 0
	output reg [24:0] ps2_mouse = 25'd0,
	output reg [10:0] ps2_key = 11'd0
);

localparam integer MOUSE_TICK = CLK_HZ / 100;
localparam integer KEY_GAP    = CLK_HZ / 500;
localparam signed [7:0] STICK_ON = 8'sd64;
localparam signed [7:0] STICK_DZ = 8'sd16;

wire mouse_mode = btn_l;

wire s0_up    = btn_up    | (stick_ly < -STICK_ON);
wire s0_down  = btn_down  | (stick_ly >  STICK_ON);
wire s0_left  = btn_left  | (stick_lx < -STICK_ON);
wire s0_right = btn_right | (stick_lx >  STICK_ON);
wire s1_up    = p1_active & (p1_up    | (p1_ly < -STICK_ON));
wire s1_down  = p1_active & (p1_down  | (p1_ly >  STICK_ON));
wire s1_left  = p1_active & (p1_left  | (p1_lx < -STICK_ON));
wire s1_right = p1_active & (p1_right | (p1_lx >  STICK_ON));

// bits: 0 right, 1 left, 2 down, 3 up, 4 fire
assign joy0 = mouse_mode ? 32'd0 :
              {27'd0, btn_a, s0_up & ~s0_down, s0_down & ~s0_up, s0_left & ~s0_right, s0_right & ~s0_left};
assign joy1 = {27'd0, p1_active & p1_a, s1_up & ~s1_down, s1_down & ~s1_up, s1_left & ~s1_right, s1_right & ~s1_left};

wire m_left  = (mouse_mode & btn_a) | btn_r | hmouse_btn[0];
wire m_right = btn_b | hmouse_btn[1];
wire m_mid   = hmouse_btn[2];

// ------------------------------------------------------------- mouse
reg [$clog2(MOUSE_TICK+1)-1:0] mtick = 0;
reg  [7:0] held = 8'd0;
reg signed [15:0] acc_x = 16'sd0, acc_y = 16'sd0;     // right / down positive
reg  [2:0] btn_sent = 3'd0;

function automatic signed [15:0] sat16(input signed [17:0] v);
	sat16 = (v > 18'sd32767) ? 16'sd32767 : (v < -18'sd32768) ? -16'sd32768 : v[15:0];
endfunction
function automatic signed [8:0] part(input signed [15:0] v);
	part = (v > 16'sd127) ? 9'sd127 : (v < -16'sd127) ? -9'sd127 : v[8:0];
endfunction
// the stick beyond the dead zone, scaled
function automatic signed [15:0] stick_step(input signed [7:0] s, input [1:0] sp);
	reg signed [15:0] v;
	v = (s > STICK_DZ || s < -STICK_DZ) ? {{8{s[7]}}, s} : 16'sd0;
	case (sp)
		2'd0: stick_step = v >>> 4;
		2'd1: stick_step = v >>> 3;
		2'd2: stick_step = v >>> 2;
		default: stick_step = v >>> 1;
	endcase
endfunction

wire dpad_any = mouse_mode && (btn_up | btn_down | btn_left | btn_right);
wire signed [15:0] dstep = 16'sd1 + {8'd0, held[7:3]} + {14'd0, mouse_speed};

always @(posedge clk) begin
	reg signed [17:0] nx, ny;
	reg signed [8:0]  px, py;
	nx = {{2{acc_x[15]}}, acc_x};
	ny = {{2{acc_y[15]}}, acc_y};
	if (hmouse_valid) begin
		nx = nx + {{2{hmouse_dx[15]}}, hmouse_dx};
		ny = ny + {{2{hmouse_dy[15]}}, hmouse_dy};
	end
	if (reset) begin
		mtick <= 0; held <= 8'd0; acc_x <= 16'sd0; acc_y <= 16'sd0; btn_sent <= 3'd0;
		ps2_mouse <= 25'd0;
	end
	else if (mtick == MOUSE_TICK - 1) begin
		mtick <= 0;
		// the sticks and the D-pad's motion of this tick
		nx = nx + stick_step(stick_rx, mouse_speed);
		ny = ny + stick_step(stick_ry, mouse_speed);
		if (dpad_any) begin
			if (btn_left)  nx = nx - dstep;
			if (btn_right) nx = nx + dstep;
			if (btn_up)    ny = ny - dstep;
			if (btn_down)  ny = ny + dstep;
			if (held != 8'hFF) held <= held + 8'd1;
		end
		else held <= 8'd0;
		px = part(sat16(nx));
		py = part(sat16(ny));
		if (px != 9'sd0 || py != 9'sd0 || {m_mid, m_right, m_left} != btn_sent) begin
			// PS/2: y up positive
			ps2_mouse <= {~ps2_mouse[24], 8'(-py), 8'(px),
			              2'b00, py > 9'sd0, px < 9'sd0, 1'b1, m_mid, m_right, m_left};
			btn_sent  <= {m_mid, m_right, m_left};
		end
		acc_x <= sat16(nx - px);
		acc_y <= sat16(ny - py);
	end
	else begin
		mtick <= mtick + 1'd1;
		acc_x <= sat16(nx);
		acc_y <= sat16(ny);
	end
end

// ------------------------------------------------------------- keys
// USB HID usage -> PS/2 set 2 {extended, code}; 0 when there is none
function automatic [8:0] hid2ps2(input [7:0] u);
	case (u)
		8'h04: hid2ps2 = 9'h01C; 8'h05: hid2ps2 = 9'h032; 8'h06: hid2ps2 = 9'h021; 8'h07: hid2ps2 = 9'h023;
		8'h08: hid2ps2 = 9'h024; 8'h09: hid2ps2 = 9'h02B; 8'h0A: hid2ps2 = 9'h034; 8'h0B: hid2ps2 = 9'h033;
		8'h0C: hid2ps2 = 9'h043; 8'h0D: hid2ps2 = 9'h03B; 8'h0E: hid2ps2 = 9'h042; 8'h0F: hid2ps2 = 9'h04B;
		8'h10: hid2ps2 = 9'h03A; 8'h11: hid2ps2 = 9'h031; 8'h12: hid2ps2 = 9'h044; 8'h13: hid2ps2 = 9'h04D;
		8'h14: hid2ps2 = 9'h015; 8'h15: hid2ps2 = 9'h02D; 8'h16: hid2ps2 = 9'h01B; 8'h17: hid2ps2 = 9'h02C;
		8'h18: hid2ps2 = 9'h03C; 8'h19: hid2ps2 = 9'h02A; 8'h1A: hid2ps2 = 9'h01D; 8'h1B: hid2ps2 = 9'h022;
		8'h1C: hid2ps2 = 9'h035; 8'h1D: hid2ps2 = 9'h01A;
		8'h1E: hid2ps2 = 9'h016; 8'h1F: hid2ps2 = 9'h01E; 8'h20: hid2ps2 = 9'h026; 8'h21: hid2ps2 = 9'h025;
		8'h22: hid2ps2 = 9'h02E; 8'h23: hid2ps2 = 9'h036; 8'h24: hid2ps2 = 9'h03D; 8'h25: hid2ps2 = 9'h03E;
		8'h26: hid2ps2 = 9'h046; 8'h27: hid2ps2 = 9'h045;
		8'h28: hid2ps2 = 9'h05A; 8'h29: hid2ps2 = 9'h076; 8'h2A: hid2ps2 = 9'h066; 8'h2B: hid2ps2 = 9'h00D;
		8'h2C: hid2ps2 = 9'h029; 8'h2D: hid2ps2 = 9'h04E; 8'h2E: hid2ps2 = 9'h055; 8'h2F: hid2ps2 = 9'h054;
		8'h30: hid2ps2 = 9'h05B; 8'h31: hid2ps2 = 9'h05D; 8'h32: hid2ps2 = 9'h05D; 8'h33: hid2ps2 = 9'h04C;
		8'h34: hid2ps2 = 9'h052; 8'h35: hid2ps2 = 9'h00E; 8'h36: hid2ps2 = 9'h041; 8'h37: hid2ps2 = 9'h049;
		8'h38: hid2ps2 = 9'h04A; 8'h39: hid2ps2 = 9'h058;
		8'h3A: hid2ps2 = 9'h005; 8'h3B: hid2ps2 = 9'h006; 8'h3C: hid2ps2 = 9'h004; 8'h3D: hid2ps2 = 9'h00C;
		8'h3E: hid2ps2 = 9'h003; 8'h3F: hid2ps2 = 9'h00B; 8'h40: hid2ps2 = 9'h083; 8'h41: hid2ps2 = 9'h00A;
		8'h42: hid2ps2 = 9'h001; 8'h43: hid2ps2 = 9'h009; 8'h44: hid2ps2 = 9'h078; 8'h45: hid2ps2 = 9'h007;
		8'h46: hid2ps2 = 9'h17C; 8'h47: hid2ps2 = 9'h07E;
		8'h49: hid2ps2 = 9'h170; 8'h4A: hid2ps2 = 9'h16C; 8'h4B: hid2ps2 = 9'h17D; 8'h4C: hid2ps2 = 9'h171;
		8'h4D: hid2ps2 = 9'h169; 8'h4E: hid2ps2 = 9'h17A; 8'h4F: hid2ps2 = 9'h174; 8'h50: hid2ps2 = 9'h16B;
		8'h51: hid2ps2 = 9'h172; 8'h52: hid2ps2 = 9'h175;
		8'h53: hid2ps2 = 9'h077; 8'h54: hid2ps2 = 9'h14A; 8'h55: hid2ps2 = 9'h07C; 8'h56: hid2ps2 = 9'h07B;
		8'h57: hid2ps2 = 9'h079; 8'h58: hid2ps2 = 9'h15A; 8'h59: hid2ps2 = 9'h069; 8'h5A: hid2ps2 = 9'h072;
		8'h5B: hid2ps2 = 9'h07A; 8'h5C: hid2ps2 = 9'h06B; 8'h5D: hid2ps2 = 9'h073; 8'h5E: hid2ps2 = 9'h074;
		8'h5F: hid2ps2 = 9'h06C; 8'h60: hid2ps2 = 9'h075; 8'h61: hid2ps2 = 9'h07D; 8'h62: hid2ps2 = 9'h070;
		8'h63: hid2ps2 = 9'h071; 8'h64: hid2ps2 = 9'h061;
		8'hE0: hid2ps2 = 9'h014; 8'hE1: hid2ps2 = 9'h012; 8'hE2: hid2ps2 = 9'h011; 8'hE3: hid2ps2 = 9'h11F;
		8'hE4: hid2ps2 = 9'h114; 8'hE5: hid2ps2 = 9'h059; 8'hE6: hid2ps2 = 9'h111; 8'hE7: hid2ps2 = 9'h127;
		default: hid2ps2 = 9'h000;
	endcase
endfunction

// key events: host keys, and the buttons' keys as they go down and up
reg  [3:0] bk_prev = 4'd0;
wire [3:0] bk_now = {btn_select, btn_start, btn_y, btn_x};
reg  [8:0] kq [0:15];             // {down, usage}
reg  [4:0] kq_wp = 5'd0, kq_rp = 5'd0;
wire [4:0] kq_level = kq_wp - kq_rp;
reg [$clog2(KEY_GAP+1)-1:0] kgap = 0;
reg  [1:0] bk_i = 2'd0;           // the button looked at this clock

always @(posedge clk) begin
	reg [8:0] code;
	if (kgap != 0) kgap <= kgap - 1'd1;
	if (reset) begin
		kq_wp <= 5'd0; kq_rp <= 5'd0; bk_prev <= 4'd0; kgap <= 0;
	end
	else begin
		// one source a clock: a host event first, else one button
		if (hkey_valid) begin
			if (kq_level != 5'd16) begin
				kq[kq_wp[3:0]] <= {hkey_down, hkey_usage};
				kq_wp <= kq_wp + 5'd1;
			end
		end
		else begin
			bk_i <= bk_i + 2'd1;
			if (bk_now[bk_i] != bk_prev[bk_i] && kq_level != 5'd16) begin
				bk_prev[bk_i] <= bk_now[bk_i];
				kq[kq_wp[3:0]] <= {bk_now[bk_i], bk_i == 2'd0 ? key_x : bk_i == 2'd1 ? key_y :
				                                  bk_i == 2'd2 ? key_start : key_select};
				kq_wp <= kq_wp + 5'd1;
			end
		end
		// out, one every KEY_GAP
		if (kq_level != 5'd0 && kgap == 0) begin
			code = hid2ps2(kq[kq_rp[3:0]][7:0]);
			kq_rp <= kq_rp + 5'd1;
			if (code != 9'd0) begin
				ps2_key <= {~ps2_key[10], kq[kq_rp[3:0]][8], code};
				kgap    <= KEY_GAP;
			end
		end
	end
end

endmodule
