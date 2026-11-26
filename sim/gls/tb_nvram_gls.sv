// Bench of the NVRAM / real-time clock (falcon_nvram, as falcon_system
// connects it, rtc 0 as the Game Bub gives it): runs on the RTL (xsim) and
// on Vivado's netlist of it (sim/gls/run_nvram_gls.sh).
// The Game Bub's sequence: the Falcon in reset for +reset_ms=<n> ms (default
// 2500: the firmware loading TOS), the NVRAM file's 50 bytes written through
// the nv port once nv_ready (gb_host's restore, +nvram=<hex file of 50
// bytes> or the bytes of the core's own falcon.nvram), the reset released;
// then TOS's accesses: index at $FF8961, data at $FF8963. Register B is set
// to binary 24 h (DM, 24/12) as EmuTOS does, the time read: with no time
// from the host the clock starts at 2026-01-01 00:00:00, a Thursday, when
// the default image is built at the first reset, and runs from then (the
// time base held while the Falcon is in reset, as falcon_nvram is written),
// so the date must be 2026-01-01 (year register 58 = 2026 - 1968), the day
// of the week 5, the time 00:00:00 (or :01); then the bench waits for the
// seconds to change
// and checks that they advanced by one and nothing else changed. The NVRAM
// bytes 14-63 must be the file's.
// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps
module tb_nvram_gls;
	localparam integer CLK_HZ = 31979167;
	localparam real    PER = 1.0e9 / CLK_HZ;

	reg clk = 0;
	always #(PER / 2) clk = !clk;

	reg         reset = 1;
	reg         cs = 0, stb = 0, we = 0, uds = 0, lds = 0;
	reg   [1:1] addr = 0;
	reg  [15:0] din = 0;
	wire [15:0] dout;
	wire        ack, irq, nv_changed, nv_ready;
	reg   [5:0] nv_addr = 0;
	reg   [7:0] nv_din = 0;
	reg         nv_wr = 0;
	wire  [7:0] nv_dout;

`ifdef GLS
	falcon_nvram dut (                    // (the netlist: CLK_HZ synthesized in)
`else
	falcon_nvram #(.CLK_HZ(CLK_HZ)) dut (
`endif
		.clk(clk), .reset(reset),
		.bus_cs(cs), .bus_stb(stb), .bus_we(we), .bus_addr(addr), .bus_uds(uds), .bus_lds(lds),
		.bus_din(din), .bus_dout(dout), .bus_ack(ack),
		.rtc(65'd0),
		.cfg_vga(1'b1), .cfg_lang(8'd0), .cfg_kbd(8'd0), .nv_init(1'b0),
		.nv_addr(nv_addr), .nv_dout(nv_dout), .nv_din(nv_din), .nv_wr(nv_wr),
		.nv_changed(nv_changed), .nv_ready(nv_ready),
		.irq(irq)
	);

	integer errors = 0;

	// a byte access at $FF8961 (a = 0) or $FF8963 (a = 1), on the odd byte;
	// between accesses the address changes (see tb_dsp_gls.sv: bus_dout is
	// combinational of registers an event-driven simulator does not see)
	task automatic acc(input bit w, input bit a, input [7:0] wd, output [7:0] rd);
		begin
			@(negedge clk);
			cs = 1; stb = 1; we = w; addr = a; uds = 0; lds = 1; din = {8'hFF, wd};
			#1;
			if (!ack) begin $display("ERROR: no ack"); errors = errors + 1; end
			rd = dout[7:0];
			@(negedge clk);
			cs = 0; stb = 0; we = 0; lds = 0; addr = !a;
		end
	endtask

	task automatic rd_reg(input [5:0] r, output [7:0] v);
		reg [7:0] d;
		begin
			acc(1, 0, {2'b00, r}, d);
			acc(0, 1, 8'h00, v);
		end
	endtask

	task automatic wr_reg(input [5:0] r, input [7:0] v);
		reg [7:0] d;
		begin
			acc(1, 0, {2'b00, r}, d);
			acc(1, 1, v, d);
		end
	endtask

	// the time registers 0, 2, 4, 6, 7, 8, 9, read once UIP (register A bit 7) is clear
	task automatic rd_time(output [7:0] t [0:6]);
		reg [7:0] a;
		integer n;
		begin
			a = 8'h80; n = 0;
			while (a[7] && n < 100000) begin rd_reg(6'd10, a); n = n + 1; end
			rd_reg(6'd0, t[0]); rd_reg(6'd2, t[1]); rd_reg(6'd4, t[2]); rd_reg(6'd6, t[3]);
			rd_reg(6'd7, t[4]); rd_reg(6'd8, t[5]); rd_reg(6'd9, t[6]);
			$display("time: %0d:%0d:%0d, day of week %0d, %0d-%0d-%0d (year register %0d)",
			         t[2], t[1], t[0], t[3], 1968 + t[6], t[5], t[4], t[6]);
		end
	endtask

	reg [7:0] img [0:49];
	reg [7:0] t1 [0:6];
	reg [7:0] t2 [0:6];
	reg [7:0] v;
	integer reset_ms = 2500;
	integer i, n, secs;
	string  nvf;
	initial begin
		if ($value$plusargs("reset_ms=%d", reset_ms)) ;
		// the core's falcon.nvram on the card (bytes 14-63)
		for (i = 0; i < 50; i = i + 1) img[i] = 8'h00;
		img[8] = 8'h11; img[9] = 8'h2e; img[10] = 8'h20; img[11] = 8'h01; img[12] = 8'hff;
		img[14] = 8'h01; img[15] = 8'h2a; img[16] = 8'h87;
		if ($value$plusargs("nvram=%s", nvf)) $readmemh(nvf, img);

		reset = 1;
		repeat (CLK_HZ / 1000) @(negedge clk);              // 1 ms
		n = 0;
		while (!nv_ready && n < 100000) begin @(negedge clk); n = n + 1; end
		if (!nv_ready) begin $display("ERROR: nv_ready never set"); errors = errors + 1; end
		for (i = 0; i < 50; i = i + 1) begin
			@(negedge clk); nv_addr = i[5:0]; nv_din = img[i]; nv_wr = 1;
			@(negedge clk); nv_wr = 0;
		end
		for (i = 1; i < reset_ms; i = i + 1) repeat (CLK_HZ / 1000) @(negedge clk);
		reset = 0;
		repeat (100) @(negedge clk);

		// the NVRAM bytes
		n = 0;
		for (i = 0; i < 50; i = i + 1) begin
			rd_reg(6'(14 + i), v);
			if (v !== img[i]) begin
				if (n < 5) $display("ERROR: NVRAM byte %0d: %02x, the file's %02x", 14 + i, v, img[i]);
				n = n + 1;
			end
		end
		if (n) errors = errors + 1;
		else $display("NVRAM: the file's 50 bytes");

		rd_reg(6'd11, v);
		wr_reg(6'd11, v | 8'h06);                           // DM (binary), 24 h
		rd_time(t1);
		secs = 0;                                           // (the time base stops in reset)
		if (t1[6] != 8'd58 || t1[5] != 8'd1 || t1[4] != 8'd1 || t1[3] != 8'd5 || t1[2] != 8'd0 ||
		    t1[1] != 8'd0 || integer'(t1[0]) < secs - 1 || integer'(t1[0]) > secs + 1) begin
			$display("ERROR: not 2026-01-01 (Thursday) 00:00:%0d", secs);
			errors = errors + 1;
		end
		// the next second
		v = t1[0]; n = 0;
		while (v == t1[0] && n < 10000000) begin rd_reg(6'd0, v); n = n + 1; end   // up to 2.5 s
		rd_time(t2);
		if (t2[0] != t1[0] + 1 || t2[1] != t1[1] || t2[2] != t1[2] || t2[3] != t1[3] ||
		    t2[4] != t1[4] || t2[5] != t1[5] || t2[6] != t1[6]) begin
			$display("ERROR: the clock did not advance by one second");
			errors = errors + 1;
		end
		if (errors) $display("SOME FAILED"); else $display("ALL PASS");
		$finish;
	end
endmodule
