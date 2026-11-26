// The Falcon's DSP56001 and sound crossbar as falcon_system connects them
// (falcon_dsp's SSI to falcon_crossbar's DSP link, the DSP's reset line
// separate), each with its own register bus (falcon_system's dev_* bus with
// its select), for synthesis out of context and the gate-level simulation of
// sim/gls/run_dsp_gls.sh. The crossbar's DMA port is a port here; the bench
// does not use it.
// SPDX-License-Identifier: GPL-2.0-or-later
module gls_dsp_top #(
	parameter CLK_HZ = 31979167
)(
	input                clk,
	input                reset,
	input                dsp_reset,
	// DSP host port ($FFA200-$FFA207)
	input                h_cs,
	input                h_stb,
	input                h_we,
	input         [2:1]  h_addr,
	input                h_uds,
	input                h_lds,
	input         [15:0] h_din,
	output        [15:0] h_dout,
	output               h_ack,
	output               hreq,
	// crossbar registers ($FF8900-$FF8943)
	input                x_cs,
	input                x_stb,
	input                x_we,
	input         [6:1]  x_addr,
	input                x_uds,
	input                x_lds,
	input         [15:0] x_din,
	output        [15:0] x_dout,
	output               x_ack,
	output               x_berr,
	// the crossbar's DMA port
	output               dma_req,
	output               dma_we,
	output        [23:1] dma_addr,
	output         [1:0] dma_be,
	output        [15:0] dma_wdata,
	input         [15:0] dma_rdata,
	input                dma_ack,
	output               sndint,
	output               soundint,
	input  signed [15:0] psg_audio,
	output signed [15:0] audio_l,
	output signed [15:0] audio_r
);
	wire        ssi_slot_stb, ssi_frame, ssi_tx_valid, ssi_tx_en, ssi_rx_en, ssi_rx_frame, ssi_hs_play_req;
	wire [15:0] ssi_rx_data, ssi_tx_data;
	wire  [7:0] ivr;

	falcon_crossbar #(.CLK_HZ(CLK_HZ)) crossbar
	(
		.clk(clk), .reset(reset),
		.tt_mode(1'b0),
		.bus_cs(x_cs), .bus_stb(x_stb), .bus_we(x_we), .bus_addr(x_addr), .bus_uds(x_uds), .bus_lds(x_lds),
		.bus_din(x_din), .bus_dout(x_dout), .bus_ack(x_ack), .bus_berr(x_berr),
		.dma_req(dma_req), .dma_we(dma_we), .dma_addr(dma_addr), .dma_be(dma_be),
		.dma_wdata(dma_wdata), .dma_rdata(dma_rdata), .dma_ack(dma_ack),
		.sndint(sndint), .soundint(soundint),
		.psg_audio(psg_audio), .mic_l(16'sd0), .mic_r(16'sd0),
		.audio_l(audio_l), .audio_r(audio_r), .audio_stb(),
		.ssi_slot_stb(ssi_slot_stb), .ssi_frame(ssi_frame), .ssi_rx_data(ssi_rx_data),
		.ssi_tx_data(ssi_tx_data), .ssi_tx_valid(ssi_tx_valid),
		.ssi_tx_en(ssi_tx_en), .ssi_rx_en(ssi_rx_en), .ssi_rx_frame(ssi_rx_frame), .ssi_hs_play_req(ssi_hs_play_req),
		.dbg_underrun()
	);

	falcon_dsp dsp
	(
		.clk(clk), .reset(reset), .dsp_reset(reset | dsp_reset),
		.bus_cs(h_cs), .bus_stb(h_stb), .bus_we(h_we), .bus_addr(h_addr), .bus_uds(h_uds), .bus_lds(h_lds),
		.bus_din(h_din), .bus_dout(h_dout), .bus_ack(h_ack),
		.hreq(hreq), .ivr(ivr), .iack(1'b0),
		.ssi_slot_stb(ssi_slot_stb), .ssi_frame(ssi_frame), .ssi_rx_data(ssi_rx_data),
		.ssi_tx_data(ssi_tx_data), .ssi_tx_valid(ssi_tx_valid),
		.ssi_tx_en(ssi_tx_en), .ssi_rx_en(ssi_rx_en), .ssi_rx_frame(ssi_rx_frame),
		.ssi_hs_play_req(ssi_hs_play_req)
	);
endmodule
