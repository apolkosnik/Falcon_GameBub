//--------------------------------------------------------------------------//
// AP68060 - pipelined MC68040                                            //
//                                                                          //
// ap68060_ram.sv - memory primitives, for Vivado 2018.3 (Game Bub)        //
//                                                                          //
// The Game Bub's version of Falcon_MiSTer's rtl/AP68060/rtl/ap68060_ram.sv  //
// (written for Quartus's inference: Vivado built the caches of those of    //
// flip-flops, 160,000 LUTs). Every module keeps its ports, its read        //
// latency and what a read of a word written at the same edge returns;    //
// the memories are written as Vivado's templates, with its attributes,     //
// as the Game Bub Minimig core's AP68040 (its patch 0001): 64 words or     //
// fewer in LUT RAM, deeper in block RAM.                                  //
//                                                                          //
//   ap68060_sdp_be   simple dual port: one write port with byte enables,   //
//                    one read port with a registered address and an        //
//                    optionally enabled output register                    //
//   ap68060_tdp      true dual port, both ports read and write, registered //
//                    addresses, unregistered outputs                       //
//   ap68060_lutram   small RAM with an asynchronous read port              //
//   ap68060_rf       the register file, of ap68060_lutram                  //
//   ap68060_sdpr     simple dual port block RAM, registered read           //
//   ap68060_pdrom    the predecoder's table, two read ports                //
//--------------------------------------------------------------------------//

module ap68060_sdp_be #(
	parameter int AW = 6,
	parameter int NB = 16,           // bytes per word
	parameter bit OREG = 1           // registered output (one more cycle)
)(
	input  logic              clk,
	input  logic              we,
	input  logic [AW-1:0]     waddr,
	input  logic [NB-1:0]     wbe,
	input  logic [NB*8-1:0]   wdata,
	input  logic [AW-1:0]     raddr,    // sampled here: data the next cycle
	input  logic              oce,      // output register enable
	output logic [NB*8-1:0]   q
);
	// Vivado's byte-write simple dual port template: one array, the byte
	// enables in a loop of one process, the read registered in the same
	// process (read first: a read of the word written in the same cycle
	// returns the old data, as the Quartus version; the users track that).
	logic [NB*8-1:0] qr;
	generate
		if (AW <= 6) begin : g_lut
			(* ram_style = "distributed" *) logic [NB*8-1:0] mem [0:(1<<AW)-1];
			always_ff @(posedge clk) begin
				for (int i = 0; i < NB; i++)
					if (we && wbe[i]) mem[waddr][i*8 +: 8] <= wdata[i*8 +: 8];
				qr <= mem[raddr];
			end
		end
		else begin : g_bram
			(* ram_style = "block" *) logic [NB*8-1:0] mem [0:(1<<AW)-1];
			always_ff @(posedge clk) begin
				for (int i = 0; i < NB; i++)
					if (we && wbe[i]) mem[waddr][i*8 +: 8] <= wdata[i*8 +: 8];
				qr <= mem[raddr];
			end
		end
	endgenerate
	generate
		if (OREG) begin : g_oreg
			always_ff @(posedge clk) if (oce) q <= qr;
		end
		else begin : g_noreg
			assign q = qr;
		end
	endgenerate
endmodule

module ap68060_tdp #(
	parameter int AW = 6,
	parameter int DW = 22
)(
	input  logic          clk,
	input  logic [AW-1:0] addr_a,
	input  logic          we_a,
	input  logic [DW-1:0] wd_a,
	output logic [DW-1:0] q_a,
	output logic [DW-1:0] qa_raw,    // ... the RAM's word, and the write laid
	output logic          qa_bv,     // over it (qa_bv: q_a is qa_bd), for a
	output logic [DW-1:0] qa_bd,     // caller comparing both in parallel
	input  logic [AW-1:0] addr_b,
	input  logic          we_b,
	input  logic [DW-1:0] wd_b,
	output logic [DW-1:0] q_b
);
	// A read returns the word as written at the edge that registered its
	// address (a write to the same word at that edge included). The RAM
	// itself reads the old word (read first); the write is laid over it by
	// a compare of registered addresses, as upstream. Vivado's true dual
	// port template: one process per port.
	logic [DW-1:0] qa_r, qb_r, wa_d, wb_d;
	logic [AW-1:0] ra, rb, wa_q, wb_q;
	logic          wa_v, wb_v;
	// (block RAM at every depth: LUT RAM has one write port)
	(* ram_style = "block" *) logic [DW-1:0] mem [0:(1<<AW)-1];
	always_ff @(posedge clk) begin
		if (we_a) mem[addr_a] <= wd_a;
		qa_r <= mem[addr_a];
	end
	always_ff @(posedge clk) begin
		if (we_b) mem[addr_b] <= wd_b;
		qb_r <= mem[addr_b];
	end
	always_ff @(posedge clk) begin
		ra   <= addr_a;
		rb   <= addr_b;
		wa_v <= we_a; wa_q <= addr_a; wa_d <= wd_a;
		wb_v <= we_b; wb_q <= addr_b; wb_d <= wd_b;
	end
	// (port B's write wins a same-word collision, as in the old order)
	assign q_a    = (wb_v && wb_q == ra) ? wb_d : (wa_v && wa_q == ra) ? wa_d : qa_r;
	assign qa_raw = qa_r;
	assign qa_bv  = (wb_v && wb_q == ra) || (wa_v && wa_q == ra);
	assign qa_bd  = (wb_v && wb_q == ra) ? wb_d : wa_d;
	assign q_b = (wb_v && wb_q == rb) ? wb_d : (wa_v && wa_q == rb) ? wa_d : qb_r;
endmodule

module ap68060_lutram #(
	parameter int AW = 4,
	parameter int DW = 50
)(
	input  logic          clk,
	input  logic          we,
	input  logic [AW-1:0] waddr,
	input  logic [DW-1:0] wdata,
	input  logic [AW-1:0] raddr,
	output logic [DW-1:0] q
);
	(* ram_style = "distributed" *) logic [DW-1:0] mem [0:(1<<AW)-1];
	initial for (int i = 0; i < (1 << AW); i++) mem[i] = '0;
	always_ff @(posedge clk) if (we) mem[waddr] <= wdata;
	assign q = mem[raddr];
endmodule

//--------------------------------------------------------------------------
// ap68060_rf: 32 x 32 register file in LUT RAM, three write ports and NR
// asynchronous read ports. Each write port owns NR copies (one per read
// port); a live value table records which port wrote each register last,
// and a read selects that port's copy. Two ports writing the same
// register in one cycle: the higher port number wins.
//--------------------------------------------------------------------------
module ap68060_rf #(
	parameter int NR = 5,
	parameter int NW = 3              // write ports (2 or 3): the later wins
)(
	input  logic        clk,
	input  logic  [2:0] we,
	input  logic  [4:0] wa [3],
	input  logic [31:0] wd [3],
	input  logic  [4:0] ra [NR],
	output logic [31:0] rd [NR]
);
	logic [1:0]  lvt [32];
	logic [31:0] q [NW][NR];
	genvar gw, gr;
	generate
		for (gw = 0; gw < NW; gw++) begin : g_w
			for (gr = 0; gr < NR; gr++) begin : g_r
				ap68060_lutram #(.AW(5), .DW(32)) bank (
					.clk(clk), .we(we[gw]), .waddr(wa[gw]), .wdata(wd[gw]),
					.raddr(ra[gr]), .q(q[gw][gr])
				);
			end
		end
	endgenerate
	initial for (int i = 0; i < 32; i++) lvt[i] = 2'd0;
	always_ff @(posedge clk)
		for (int w = 0; w < NW; w++)
			if (we[w]) lvt[wa[w]] <= 2'(w);
	always_comb
		for (int r = 0; r < NR; r++)
			rd[r] = q[lvt[ra[r]]][r];
endmodule

//--------------------------------------------------------------------------
// ap68060_sdpr: simple dual-port RAM, one write and one read port, the
// read registered (data the cycle after its address). A read of the word
// written at the same edge is undefined: the caller handles it.
//--------------------------------------------------------------------------
module ap68060_sdpr #(
	parameter int AW = 8,
	parameter int DW = 32
)(
	input  logic          clk,
	input  logic          we,
	input  logic [AW-1:0] waddr,
	input  logic [DW-1:0] wdata,
	input  logic [AW-1:0] raddr,
	output logic [DW-1:0] q
);
	generate
		if (AW <= 6) begin : g_lut
			(* ram_style = "distributed" *) logic [DW-1:0] mem [0:(1<<AW)-1];
			initial for (int i = 0; i < (1 << AW); i++) mem[i] = '0;
			always_ff @(posedge clk) begin
				if (we) mem[waddr] <= wdata;
				q <= mem[raddr];
			end
		end
		else begin : g_bram
			(* ram_style = "block" *) logic [DW-1:0] mem [0:(1<<AW)-1];
			initial for (int i = 0; i < (1 << AW); i++) mem[i] = '0;
			always_ff @(posedge clk) begin
				if (we) mem[waddr] <= wdata;
				q <= mem[raddr];
			end
		end
	endgenerate
endmodule

//--------------------------------------------------------------------------
// ap68060_pdrom: the predecoder's table (tools/ucode.py emit_pdrom), one
// word per operation word bits 15:3, in block RAM with two read ports
// (the fetch unit's two words a cycle); the words read a cycle after their
// addresses
//--------------------------------------------------------------------------
module ap68060_pdrom
	import ap68060_upkg::*;
(
	input  logic        clk,
	input  logic [12:0] a0,
	input  logic [12:0] a1,
	output pdw_t        q0,
	output pdw_t        q1
);
	(* rom_style = "block" *) logic [32:0] pd_rom [0:8191];
	initial begin
`include "gen/ap68060_pd_rom.svh"
	end
	always_ff @(posedge clk) begin
		q0 <= pdw_t'(pd_rom[a0]);
		q1 <= pdw_t'(pd_rom[a1]);
	end
endmodule
