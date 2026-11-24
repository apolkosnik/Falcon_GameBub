// Unit bench of gb_sdram: falcon_memarb's DDRAM protocol (a command held
// until BUSY is low, read bursts of 1 or 4 beats, single-beat writes with
// byte enables) at random over a few rows of every bank, against the SDRAM
// model (sim/rtl/sdram_sim.sv: protocol and timing checks at the board's
// clock, 10.42 ns) and a shadow memory. Every read beat is compared, every
// command's BUSY / DOUT_READY sequence checked.
//   sim/sdr/run_sdr.sh [commands] [seed]
// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ps/1ps
`define TB_TOP tb_sdram

module tb_sdram;

reg mmcm_locked = 1'b1;

// clk_mem 95.9375 MHz, clk_sys = clk_mem / 3 (edges aligned), clk_sdram =
// clk_mem delayed by 912 ps
localparam integer TM = 10424;
reg clk_mem = 0, clk_sys = 0, clk_sdram = 0;
integer phase = 0;
always #(TM/2) begin
	clk_mem = ~clk_mem;
	if (clk_mem) begin
		if (phase == 0) clk_sys = 1;
		phase = (phase + 1) % 3;
	end
	else if (phase == 2) clk_sys = 0;   // high for 1.5 clk_mem periods
end
always @(clk_mem) clk_sdram <= #912 clk_mem;

reg reset_mem = 1'b1;

wire        busy, rdy;
wire [63:0] dout;
reg   [7:0] burstcnt = 8'd1;
reg  [28:0] addr = 29'd0;
reg         rd = 1'b0, we = 1'b0;
reg  [63:0] din = 64'd0;
reg   [7:0] be = 8'hFF;

wire        sd_clk, sd_ras, sd_cas, sd_we, sd_oe;
wire  [1:0] sd_cke, sd_cs, sd_dqm, sd_ba;
wire [12:0] sd_a;
wire [15:0] sd_dout, mdl_dout;
wire        mdl_oe, init_done;

gb_sdram #(.POWERUP(2000)) dut
(
	.clk_sys(clk_sys), .DDRAM_BUSY(busy), .DDRAM_BURSTCNT(burstcnt), .DDRAM_ADDR(addr),
	.DDRAM_DOUT(dout), .DDRAM_DOUT_READY(rdy), .DDRAM_RD(rd), .DDRAM_DIN(din),
	.DDRAM_BE(be), .DDRAM_WE(we),
	.clk_mem(clk_mem), .clk_sdram(clk_sdram), .reset_mem(reset_mem),
	.sd_clk(sd_clk), .sd_cke(sd_cke), .sd_cs(sd_cs), .sd_ras(sd_ras), .sd_cas(sd_cas),
	.sd_we(sd_we), .sd_dqm(sd_dqm), .sd_ba(sd_ba), .sd_addr(sd_a),
	.sd_data_in(mdl_oe ? mdl_dout : 16'hZZZZ), .sd_data_out(sd_dout), .sd_data_oe(sd_oe),
	.init_done(init_done), .dbg_cmds()
);

// the board: the pins change a little after the clk_mem edge (I/O block
// registers), the model samples at the SDRAM clock's rising edge
sdram_sim #(.T_RCD(2), .T_RP(2), .T_RAS(5), .T_RC(7), .T_RFC(7), .T_REFI(749)) sdram
(
	.clk(sd_clk), .cke(sd_cke[0]), .cs_n(sd_cs[0]), .ras_n(sd_ras), .cas_n(sd_cas), .we_n(sd_we),
	.ba(sd_ba), .a(sd_a), .dqm(sd_dqm), .dq_in(sd_dout), .dq_in_en(sd_oe),
	.dq_out(mdl_dout), .dq_out_en(mdl_oe)
);

integer errors = 0;
always @(posedge sd_clk) if (sd_oe && mdl_oe) begin
	$display("ERROR: both drive the data bus at %0t", $time);
	errors = errors + 1;
end
always @(posedge sd_clk) if (sd_cs[1] !== 1'b1) begin
	$display("ERROR: chip 1 selected");
	errors = errors + 1;
end

// shadow of the beats used: 4 banks x 3 rows x 128 beats
reg [63:0] shadow [0:1535];
function automatic [20:0] beat_of(input integer i);
	integer bank, row, col;
	bank = (i / 128) % 4;
	row  = i / 512;
	col  = i % 128;
	beat_of = {row[11:0] * 12'd37 + 12'd5, bank[1:0], col[6:0]};
endfunction

integer seed, ncmd, n, i, b, idx, nb, reads = 0, writes = 0, beats = 0;
integer t0, waited;
reg [63:0] got, want, mask;

initial begin
	if (!$value$plusargs("seed=%d", seed)) seed = 1;
	if (!$value$plusargs("cmds=%d", ncmd)) ncmd = 20000;
	for (i = 0; i < 1536; i = i + 1) shadow[i] = 64'd0;
	repeat (10) @(posedge clk_mem);
	reset_mem = 1'b0;
	@(posedge clk_sys);
	wait (!busy);
	// clear the shadowed beats
	for (i = 0; i < 1536; i = i + 1) begin
		@(posedge clk_sys);
		addr <= {8'h06, beat_of(i)}; din <= 64'd0; be <= 8'hFF; we <= 1'b1; burstcnt <= 8'd1;
		@(posedge clk_sys);
		while (busy) @(posedge clk_sys);
		we <= 1'b0;
	end
	for (n = 0; n < ncmd; n = n + 1) begin
		// mostly near the last address, sometimes anywhere (row misses)
		idx = ($urandom(seed) % 4 == 0) ? $urandom % 1536 : (idx + $urandom % 8) % 1536;
		seed = seed + 1;
		@(posedge clk_sys);
		if ($urandom % 3 == 0) begin
			// write one beat
			din  <= {$urandom, $urandom};
			be   <= ($urandom % 2) ? 8'hFF : $urandom;
			addr <= {8'h06, beat_of(idx)};
			we   <= 1'b1; burstcnt <= 8'd1;
			@(posedge clk_sys);
			while (busy) @(posedge clk_sys);
			we <= 1'b0;
			for (b = 0; b < 8; b = b + 1) if (be[b]) shadow[idx][8*b +: 8] = din[8*b +: 8];
			writes = writes + 1;
			if (rdy) begin $display("ERROR: DOUT_READY on a write"); errors = errors + 1; end
		end
		else begin
			nb = ($urandom % 2) ? 4 : 1;
			idx = idx & ~(nb - 1);
			addr <= {8'h06, beat_of(idx)};
			rd <= 1'b1; burstcnt <= nb[7:0];
			@(posedge clk_sys);
			while (busy && !rdy) @(posedge clk_sys);
			rd <= 1'b0;
			for (b = 0; b < nb; b = b + 1) begin
				waited = 0;
				while (!rdy) begin
					@(posedge clk_sys);
					waited = waited + 1;
					if (waited > 200) begin $display("ERROR: read beat %0d never came", b); $finish; end
				end
				want = shadow[(idx & ~3) | ((idx + b) & 3)];
				if (nb == 1) want = shadow[idx];
				if (dout !== want) begin
					$display("ERROR: read beat %0d of %0d at %h: %h, want %h", b, nb, beat_of(idx), dout, want);
					errors = errors + 1;
				end
				beats = beats + 1;
				@(posedge clk_sys);
			end
			if (rdy) begin $display("ERROR: extra read beat"); errors = errors + 1; end
			reads = reads + 1;
		end
	end
	// 70 ms with nothing to do: the refresh alone (the model fails more
	// than 8 owed)
	repeat (70 * 31979) @(posedge clk_sys);
	$display("gb_sdram: %0d writes, %0d reads (%0d beats), %0d errors, %0d model errors, model: %0d READ %0d WRITE",
	         writes, reads, beats, errors, sdram.errors, sdram.reads, sdram.writes);
	if (errors == 0 && sdram.errors == 0) $display("PASS"); else $display("FAIL");
	$finish;
end

endmodule
