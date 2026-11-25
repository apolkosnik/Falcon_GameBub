//--------------------------------------------------------------------------//
// AP030 - MC68030 compatible CPU                                           //
//                                                                          //
// ap030_l2ram.sv - the RAMs of the Fast RAM cache (ap030_fastram_fe), for  //
// Vivado 2018.3 (Game Bub): Falcon_MiSTer's rtl/AP68060/rtl/fastram/       //
// ap030_l2ram.sv wrote the byte enables through a packed [3:0][7:0] array, //
// which Vivado built of flip-flops; these are its byte-write simple dual   //
// port template (block RAM). The same ports and behaviour:                //
//   ap030_l2ram_be  simple dual-port, 32 bits with byte enables            //
//   ap030_l2ram     simple dual-port, plain                                //
// One clock, registered read. A read of the address being written returns //
// the old data; the user never relies on it.                               //
//--------------------------------------------------------------------------//

module ap030_l2ram_be #(parameter AW = 9)
(
	input               clk,
	input               we,
	input      [AW-1:0] wa,
	input         [3:0] be,         // bit 3 = D31-D24
	input        [31:0] wd,
	input      [AW-1:0] ra,
	output reg   [31:0] q
);

(* ram_style = "block" *) reg [31:0] ram [0:(1<<AW)-1];

always @(posedge clk) begin
	for (int i = 0; i < 4; i++)
		if (we && be[i]) ram[wa][i*8 +: 8] <= wd[i*8 +: 8];
	q <= ram[ra];
end

endmodule

module ap030_l2ram #(parameter AW = 9, parameter DW = 20)
(
	input               clk,
	input               we,
	input      [AW-1:0] wa,
	input      [DW-1:0] wd,
	input      [AW-1:0] ra,
	output reg [DW-1:0] q
);

(* ram_style = "block" *) reg [DW-1:0] ram [0:(1<<AW)-1];

always @(posedge clk) begin
	if (we) ram[wa] <= wd;
	q <= ram[ra];
end

endmodule
