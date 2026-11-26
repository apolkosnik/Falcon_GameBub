// Bench of the DSP56001 and the sound crossbar (gls_dsp_top): runs on the
// RTL (xsim) and on Vivado's netlist of it (sim/gls/run_dsp_gls.sh).
// The 68030's side is played through the real host port and crossbar
// registers, with the accesses of the test ROMs of sim/asm:
//   echo  (dsptest.s): the DSP reset by its reset line and bootstrapped with
//         a host echo program through TXH/TXM/TXL (waiting for TXDE); 16
//         words sent, each must come back plus one (RXDF).
//   poll  (dspsnd.s): a program polling the SSI's TDE sends a sawtooth to
//         the SSI, the crossbar connects the DSP transmitter to the DAC
//         (25 MHz clock, divider 1: 49170 Hz, no handshake), the codec's
//         adder the DAC only, no attenuation.
//   irq   (dspsndi.s): the same sawtooth sent from the SSI transmit
//         interrupt (a fast interrupt at P:$0010 and P:$0012).
// For poll and irq every sample of the codec's output is checked over
// +ms=<n> ms (default 20) after 2 ms: the left channel 2 * step on from the
// last sample, the right channel step on from the left (modulo 65536, give
// or take the one that the attenuation's (x * 65535) >> 16 takes), no X,
// and 49170 samples a second. +step=<n> (default 256) is the sawtooth's step
// per slot in the 16-bit word.
// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps
module tb_dsp_gls;
	localparam integer CLK_HZ = 31979167;
	localparam real    PER = 1.0e9 / CLK_HZ;

	reg clk = 0;
	always #(PER / 2) clk = !clk;

	reg         reset = 1, dsp_reset = 0;
	reg         h_cs = 0, h_stb = 0, h_we = 0, h_uds = 0, h_lds = 0;
	reg   [2:1] h_addr = 0;
	reg  [15:0] h_din = 0;
	wire [15:0] h_dout;
	wire        h_ack, hreq;
	reg         x_cs = 0, x_stb = 0, x_we = 0, x_uds = 0, x_lds = 0;
	reg   [6:1] x_addr = 0;
	reg  [15:0] x_din = 0;
	wire [15:0] x_dout;
	wire        x_ack, x_berr;
	wire signed [15:0] audio_l, audio_r;

	gls_dsp_top dut (
		.clk(clk), .reset(reset), .dsp_reset(dsp_reset),
		.h_cs(h_cs), .h_stb(h_stb), .h_we(h_we), .h_addr(h_addr), .h_uds(h_uds), .h_lds(h_lds),
		.h_din(h_din), .h_dout(h_dout), .h_ack(h_ack), .hreq(hreq),
		.x_cs(x_cs), .x_stb(x_stb), .x_we(x_we), .x_addr(x_addr), .x_uds(x_uds), .x_lds(x_lds),
		.x_din(x_din), .x_dout(x_dout), .x_ack(x_ack), .x_berr(x_berr),
		.dma_req(), .dma_we(), .dma_addr(), .dma_be(), .dma_wdata(),
		.dma_rdata(16'h0000), .dma_ack(1'b0),
		.sndint(), .soundint(),
		.psg_audio(16'sd0), .audio_l(audio_l), .audio_r(audio_r)
	);

	integer errors = 0;

	// ---- the 68030's accesses (falcon_cpubus: dev_stb one clock, dev_cs
	// held until the device's ack) ----
	task automatic h_access(input bit we, input [2:0] off, input [7:0] wd, output [7:0] rd);
		integer n;
		bit got;
		begin
			@(negedge clk);
			h_cs = 1; h_stb = 1; h_we = we; h_addr = off[2:1];
			h_uds = !off[0]; h_lds = off[0];
			h_din = off[0] ? {8'hFF, wd} : {wd, 8'hFF};
			#1;
			got = h_ack;
			rd = off[0] ? h_dout[7:0] : h_dout[15:8];
			@(negedge clk);
			h_stb = 0;
			n = 0;
			while (!got && n < 16) begin
				#1;
				if (h_ack) begin got = 1; rd = off[0] ? h_dout[7:0] : h_dout[15:8]; end
				else @(negedge clk);
				n = n + 1;
			end
			if (!got) begin $display("ERROR: no host port ack (offset %0d)", off); errors = errors + 1; end
			// between accesses the address changes (it is a don't care while
			// the port is not selected): dsp_periph's bus_dout is a continuous
			// assignment of host_byte(bus_addr), a function that reads the
			// registers as module variables, which an event-driven simulator
			// (xsim on the RTL) evaluates again only when bus_addr changes, so
			// a poll of ISR at an unchanged address would read a stale ISR.
			// Synthesis, Verilator and the netlist have it combinational.
			h_cs = 0; h_we = 0; h_uds = 0; h_lds = 0; h_addr = ~h_addr;
		end
	endtask

	task automatic x_write(input [6:1] wa, input bit uds, input bit lds, input [15:0] d);
		integer n;
		bit got;
		begin
			@(negedge clk);
			x_cs = 1; x_stb = 1; x_we = 1; x_addr = wa; x_uds = uds; x_lds = lds; x_din = d;
			#1;
			got = x_ack;
			@(negedge clk);
			x_stb = 0;
			n = 0;
			while (!got && n < 16) begin
				#1;
				if (x_ack) got = 1; else @(negedge clk);
				n = n + 1;
			end
			if (!got) begin $display("ERROR: no crossbar ack (word %02x)", wa); errors = errors + 1; end
			x_cs = 0; x_we = 0; x_uds = 0; x_lds = 0;
		end
	endtask

	// a 24-bit word to the DSP, once TXDE (ISR bit 1, $FFA202)
	task automatic txword(input [23:0] w);
		reg [7:0] isr, dummy;
		integer n;
		begin
			isr = 0; n = 0;
			while (!isr[1] && n < 100000) begin h_access(0, 3'd2, 8'h00, isr); n = n + 1; end
			if (!isr[1]) begin $display("ERROR: TXDE never set"); errors = errors + 1; end
			h_access(1, 3'd5, w[23:16], dummy);
			h_access(1, 3'd6, w[15:8], dummy);
			h_access(1, 3'd7, w[7:0], dummy);
		end
	endtask

	// a word from the DSP once RXDF (ISR bit 0); ok = 0 when none comes
	task automatic rxword(output [23:0] w, output bit ok);
		reg [7:0] isr, b;
		integer n;
		begin
			isr = 0; n = 0;
			while (!isr[0] && n < 20000) begin h_access(0, 3'd2, 8'h00, isr); n = n + 1; end
			ok = isr[0];
			w = 0;
			if (ok) begin
				h_access(0, 3'd5, 8'h00, b); w[23:16] = b;
				h_access(0, 3'd6, 8'h00, b); w[15:8]  = b;
				h_access(0, 3'd7, 8'h00, b); w[7:0]   = b;
			end
		end
	endtask

	// reset everything, then the DSP's reset line as Dsp_ExecBoot (PSG port A
	// bit 4 high, then low) and the 512-word bootstrap
	reg [23:0] prog [0:511];
	task automatic boot;
		integer i;
		begin
			reset = 1; dsp_reset = 0;
			repeat (16) @(negedge clk);
			reset = 0;
			repeat (16) @(negedge clk);
			dsp_reset = 1;
			repeat (60) @(negedge clk);
			dsp_reset = 0;
			repeat (4) @(negedge clk);
			for (i = 0; i < 512; i = i + 1) txword(prog[i]);
		end
	endtask

	task automatic clear_prog;
		integer i;
		begin for (i = 0; i < 512; i = i + 1) prog[i] = 24'h000000; end
	endtask

	// ---- the codec's output ----
	integer step = 256;
	reg     checking = 0;
	integer n_smp = 0, bad_step = 0, bad_lr = 0, bad_x = 0;
	reg  [15:0] pl = 0, pr = 0;
	reg         have = 0;
	always @(posedge clk) if (checking) begin
		if ($isunknown({audio_l, audio_r})) begin
			if (bad_x < 5) $display("ERROR: audio unknown at %t: %h %h", $time, audio_l, audio_r);
			bad_x = bad_x + 1;
		end
		else if (!have || audio_l != pl || audio_r != pr) begin
			if (have) begin : chk
				reg signed [15:0] d, lr;
				d  = audio_l - pl;
				lr = audio_r - audio_l;
				n_smp = n_smp + 1;
				if (d < 2 * step - 1 || d > 2 * step + 1) begin
					if (bad_step < 10) $display("ERROR: left %0d after %0d (step %0d)", audio_l, $signed(pl), d);
					bad_step = bad_step + 1;
				end
				if (lr < step - 1 || lr > step + 1) begin
					if (bad_lr < 10) $display("ERROR: right %0d with left %0d", audio_r, audio_l);
					bad_lr = bad_lr + 1;
				end
			end
			have = 1;
			pl = audio_l; pr = audio_r;
		end
	end

	task automatic check_audio(input string name, input integer ms);
		integer clocks, want;
		begin
			repeat (CLK_HZ / 500) @(negedge clk);          // 2 ms
			n_smp = 0; bad_step = 0; bad_lr = 0; bad_x = 0; have = 0;
			checking = 1;
			clocks = (CLK_HZ / 1000) * ms;
			repeat (clocks) @(negedge clk);
			checking = 0;
			want = (clocks * 64'd49170) / CLK_HZ;
			if (bad_step || bad_lr || bad_x || n_smp < want - 2 || n_smp > want + 2) begin
				$display("%s: FAIL: %0d samples (%0d expected), %0d steps wrong, %0d right channels wrong, %0d unknown",
				         name, n_smp, want, bad_step, bad_lr, bad_x);
				errors = errors + 1;
			end
			else $display("%s: ok: %0d samples (%0d expected), every step %0d, right channel %0d on",
			              name, n_smp, want, 2 * step, step);
		end
	endtask

	task automatic xbar_dsp_to_dac;
		begin
			x_write(6'h10, 1, 0, 16'h0000);   // $FF8920: one track
			x_write(6'h18, 1, 1, 16'h0090);   // $FF8930: DSP transmit connected, 25 MHz, no handshake
			x_write(6'h19, 1, 1, 16'h2000);   // $FF8932: the DAC from the DSP transmitter
			x_write(6'h1a, 0, 1, 16'h0001);   // $FF8935: divider 1
			x_write(6'h1b, 0, 1, 16'h0002);   // $FF8937: the adder from the crossbar
			x_write(6'h1d, 1, 1, 16'h0000);   // $FF893A: no attenuation
		end
	endtask

	integer ms = 20;
	integer i, good;
	reg [23:0] w, want_w;
	bit ok;
	initial begin
		if ($value$plusargs("step=%d", step)) ;
		if ($value$plusargs("ms=%d", ms)) ;

		// ---- echo (dsptest.s) ----
		clear_prog;
		prog[0] = 24'h44F400; prog[1] = 24'h000001; prog[2] = 24'h0AA980; prog[3] = 24'h000002;
		prog[4] = 24'h084E2B; prog[5] = 24'h200040; prog[6] = 24'h0AA981; prog[7] = 24'h000006;
		prog[8] = 24'h08CE2B; prog[9] = 24'h0C0002;
		boot;
		w = 24'h123456; good = 0;
		for (i = 0; i < 16; i = i + 1) begin
			txword(w);
			rxword(want_w, ok);
			if (ok && want_w == ((w + 1) & 24'hFFFFFF)) good = good + 1;
			else $display("ERROR: echo of %06x: %06x%s", w, want_w, ok ? "" : " (none)");
			w = (w + 24'h010203) & 24'h3FFFFF;
		end
		if (good == 16) $display("echo: ok: 16 of 16 words");
		else begin $display("echo: FAIL: %0d of 16 words", good); errors = errors + 1; end

		// ---- poll (dspsnd.s) ----
		clear_prog;
		prog[8'h00] = 24'h08F4AC; prog[8'h01] = 24'h004100;   // movep #$4100,x:$ffec  CRA
		prog[8'h02] = 24'h08F4AD; prog[8'h03] = 24'h001800;   // movep #$1800,x:$ffed  CRB: TE, network
		prog[8'h04] = 24'h08F4A1; prog[8'h05] = 24'h0001F8;   // movep #$01f8,x:$ffe1  PCC
		prog[8'h06] = 24'h44F400; prog[8'h07] = 24'(step) << 8; // move #step,x0
		prog[8'h08] = 24'h200013;                             // clr a
		prog[8'h09] = 24'h0AAE86; prog[8'h0A] = 24'h000009;   // jclr #6,x:$ffee,$09
		prog[8'h0B] = 24'h08CC2F;                             // movep a1,x:$ffef
		prog[8'h0C] = 24'h200040;                             // add x0,a
		prog[8'h0D] = 24'h0C0009;                             // jmp $09
		boot;
		xbar_dsp_to_dac;
		check_audio("poll", ms);

		// ---- irq (dspsndi.s) ----
		clear_prog;
		prog[8'h00] = 24'h0C0040;                             // jmp $40
		prog[8'h10] = 24'h08CC2F; prog[8'h11] = 24'h200040;   // SSI transmit: movep a1,x:$ffef; add x0,a
		prog[8'h12] = 24'h08CC2F; prog[8'h13] = 24'h200040;   // with exception: the same
		prog[8'h40] = 24'h08F4AC; prog[8'h41] = 24'h004100;   // CRA
		prog[8'h42] = 24'h08F4AD; prog[8'h43] = 24'h005800;   // CRB: TIE, TE, network
		prog[8'h44] = 24'h08F4A1; prog[8'h45] = 24'h0001F8;   // PCC
		prog[8'h46] = 24'h08F4BF; prog[8'h47] = 24'h003000;   // IPR: the SSI at level 2
		prog[8'h48] = 24'h44F400; prog[8'h49] = 24'(step) << 8; // move #step,x0
		prog[8'h4A] = 24'h200013;                             // clr a
		prog[8'h4B] = 24'h00FCB8;                             // andi #$fc,mr
		prog[8'h4C] = 24'h0C004C;                             // jmp $4c
		boot;
		xbar_dsp_to_dac;
		check_audio("irq", ms);

		if (errors) $display("SOME FAILED"); else $display("ALL PASS");
		$finish;
	end
endmodule
