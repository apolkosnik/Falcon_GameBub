// Game Bub Falcon: falcon_memarb's DDR3 port (MiSTer DDRAM_*, 64-bit beats)
// on the first SDRAM chip of the board (16 bit, 4 banks x 8192 rows x 512
// columns, 32 MB).
//
// The Falcon's 16 MB guest space is the first 16 MB of the chip; DDRAM_ADDR
// bits 20:0 are the beat (guest byte address / 8). With CHIP1 (the 68060
// variant's Fast RAM, CT60 mode) the second chip holds guest $01000000 -
// $02FFFFFF: a beat with DDRAM_ADDR bits 24:21 not 0 is beat
// DDRAM_ADDR[22:0] - $200000 of chip 1; both chips are initialised and
// refreshed together, each has its own open rows. Beat b is the four words
// 4b..4b+3: column b[6:0]*4, bank b[8:7], row b[21:9]; word i holds the
// beat's bytes 2i (bits 7:0) and 2i+1 (bits 15:8): DDRAM byte order, which
// falcon_memarb makes the guest's (it swaps at its side). Without CHIP1 the
// second chip is not used (deselected, never initialised).
//
// The DDRAM side (clk_sys) is the contract falcon_memarb relies on: a
// command (RD with BURSTCNT 1 or 4, or WE of one beat with byte enables) is
// accepted at a clock edge where BUSY is low (a read of 1 to 4 beats: 4
// from falcon_memarb, 2 from the Fast RAM's line reads); BUSY is then high
// until the command is complete (a write: in the SDRAM; a read: its last beat handed
// over); read beats come with DOUT_READY, one per clk_sys clock at most.
// One command at a time.
//
// The SDRAM side runs on clk_mem (3 x clk_sys from the same MMCM, edges
// aligned): the request and completion cross as toggles between registers
// of the two clocks, which Vivado times as synchronous paths (the shortest
// clk_sys -> clk_mem and clk_mem -> clk_sys edge pairs are one clk_mem
// period apart).
//
// Pins as the Game Bub Minimig core drives the same SDRAM: the SDRAM clock
// is clk_sdram (clk_mem delayed) inverted, forwarded by an ODDR; command,
// address, DQM and data out from I/O block registers; read data into I/O
// block registers (sd_in_q). CAS latency 3: a READ issued in cycle C (on
// the pins during C) gives its words in sd_in_q during C+4..C+7. Burst
// length 4 for reads, single-location writes: a beat is one READ, or four
// WRITEs in C..C+3 (unwritten bytes masked by DQM). Rows
// stay open (one per bank) until a refresh or another row of the bank is
// needed. ACTIVE to READ/WRITE and PRECHARGE to ACTIVE take T_RCD / T_RP
// clocks, ACTIVE to PRECHARGE T_RAS, the last write word to PRECHARGE
// T_WR, REFRESH to anything T_RFC; a WRITE never drives the bus while read
// data may still be on it.
//
// SPDX-License-Identifier: GPL-2.0-or-later

module gb_sdram
#(
	parameter integer CLK_HZ  = 95937500,
	parameter bit     CHIP1   = 1'b0,     // the second chip: Fast RAM
	parameter integer T_RCD   = 3,
	parameter integer T_RP    = 3,
	parameter integer T_RAS   = 5,
	parameter integer T_WR    = 2,
	parameter integer T_RFC   = 8,
	parameter integer T_MRD   = 2,
	parameter integer REFI    = CLK_HZ / 130000,   // 7.7 us (8192 rows in 64 ms: 7.8 us)
	parameter integer POWERUP = CLK_HZ / 5000      // 200 us
)
(
	// DDRAM slave (clk_sys)
	input             clk_sys,
	output reg        DDRAM_BUSY = 1'b1,
	input       [7:0] DDRAM_BURSTCNT,
	input      [28:0] DDRAM_ADDR,
	output reg [63:0] DDRAM_DOUT = 64'd0,
	output reg        DDRAM_DOUT_READY = 1'b0,
	input             DDRAM_RD,
	input      [63:0] DDRAM_DIN,
	input       [7:0] DDRAM_BE,
	input             DDRAM_WE,

	// SDRAM (clk_mem)
	input             clk_mem,
	input             clk_sdram,
	input             reset_mem,      // in clk_mem: (re)initialise
	output            sd_clk,
	output      [1:0] sd_cke,
	output reg  [1:0] sd_cs = 2'b11,
	output reg        sd_ras = 1'b1,
	output reg        sd_cas = 1'b1,
	output reg        sd_we = 1'b1,
	output reg  [1:0] sd_dqm = 2'b11,
	output reg  [1:0] sd_ba = 2'b00,
	output reg [12:0] sd_addr = 13'd0,
	input      [15:0] sd_data_in,
	output reg [15:0] sd_data_out = 16'd0,
	output reg        sd_data_oe = 1'b0,

	output reg        init_done = 1'b0,   // clk_mem
	output reg [31:0] dbg_cmds = 32'd0    // commands done (clk_mem)
);

assign sd_cke = 2'b11;

ODDR #(
	.DDR_CLK_EDGE("OPPOSITE_EDGE"),
	.INIT(1'b0),
	.SRTYPE("SYNC")
) sd_clk_oddr (
	.Q (sd_clk),
	.C (clk_sdram),
	.CE(1'b1),
	.D1(1'b0),
	.D2(1'b1),
	.R (1'b0),
	.S (1'b0)
);

// ===========================================================================
// clk_sys: the DDRAM side
// ===========================================================================
reg        s_req = 1'b0;          // toggles with each command
reg        s_we;
reg  [2:0] s_beats;               // beats - 1
reg [21:0] s_addr;
reg        s_chip;
reg [63:0] s_wdata;
reg  [7:0] s_be;
reg  [1:0] s_rcnt = 2'd0;         // read beats handed over (mod 4)
reg        s_busy = 1'b0;

wire       m_done_tgl;            // from clk_mem
wire [2:0] m_rcnt;                // read beats in rbuf (mod 8)
reg [63:0] rbuf [0:3];            // read beats (written in clk_mem)
wire       m_init;

reg  [2:0] s_rseen = 3'd0;
reg        s_done_seen = 1'b0;

always @(posedge clk_sys) begin
	DDRAM_DOUT_READY <= 1'b0;
	if (!s_busy) begin
		if ((DDRAM_RD || DDRAM_WE) && !DDRAM_BUSY) begin
			s_we    <= DDRAM_WE;
			s_beats <= (DDRAM_WE || DDRAM_BURSTCNT[2:0] == 3'd0) ? 3'd0 :
			           (DDRAM_BURSTCNT[2:0] > 3'd4) ? 3'd3 : DDRAM_BURSTCNT[2:0] - 3'd1;
			s_chip  <= CHIP1 && (DDRAM_ADDR[24:21] != 4'd0);
			s_addr  <= (CHIP1 && DDRAM_ADDR[24:21] != 4'd0) ? 22'(DDRAM_ADDR[22:0] - 23'h200000)
			                                              : {1'b0, DDRAM_ADDR[20:0]};
			s_wdata <= DDRAM_DIN;
			s_be    <= DDRAM_BE;
			s_req   <= ~s_req;
			s_busy  <= 1'b1;
			DDRAM_BUSY <= 1'b1;
		end
		else DDRAM_BUSY <= ~m_init;
	end
	else begin
		// read beats as they arrive
		if (!s_we && s_rseen != m_rcnt) begin
			DDRAM_DOUT       <= rbuf[s_rseen[1:0]];
			DDRAM_DOUT_READY <= 1'b1;
			s_rseen          <= s_rseen + 3'd1;
		end
		if (m_done_tgl != s_done_seen && (s_we || s_rseen == m_rcnt)) begin
			s_done_seen <= m_done_tgl;
			s_busy      <= 1'b0;
			DDRAM_BUSY  <= 1'b0;
		end
	end
end

// ===========================================================================
// clk_mem: the SDRAM side
// ===========================================================================
// LOAD MODE: single-location writes, CAS latency 3, sequential, burst of 4
localparam [12:0] MODE = 13'b000_1_00_011_0_010;

reg        m_done = 1'b0;
reg  [2:0] m_rc = 3'd0;
reg        m_init_r = 1'b0;
assign     m_done_tgl = m_done;
assign     m_rcnt = m_rc;
assign     m_init = m_init_r;

reg        m_seen = 1'b0;         // the last request toggle taken
reg        c_we;
reg  [2:0] c_last;
reg [21:0] c_addr;
reg        c_chip;
reg [63:0] c_wdata;
reg  [7:0] c_be;
reg  [2:0] c_beat;                // beat being issued
reg  [2:0] c_got;                 // beats received (reads)

reg  [7:0] row_open = 8'd0;        // {chip, bank}
reg [12:0] row_of [0:7];

localparam [3:0] S_POWER = 4'd0, S_INIT = 4'd1, S_IDLE = 4'd2, S_ACCESS = 4'd3,
                 S_WAIT = 4'd4, S_RDWAIT = 4'd5, S_REFRESH = 4'd6, S_FINISH = 4'd7;
reg  [3:0] state = S_POWER;
reg [15:0] cnt = 16'd0;
reg  [3:0] istep = 4'd0;
reg [11:0] ref_cnt = 12'd0;
reg        ref_due = 1'b0;

// timing since the last ACTIVE, READ, write word
reg  [3:0] act_age = 4'd15;
reg  [3:0] rd_age = 4'd15;
reg  [3:0] wr_age = 4'd15;

// read data pipeline: a READ in cycle C has its words in sd_in_q in C+4..C+7
reg [15:0] sd_in_q;
always @(posedge clk_mem) sd_in_q <= sd_data_in;
reg  [7:0] rp_v = 8'd0;           // word arrives (shifted each clock)
reg [47:0] racc;
reg  [1:0] rword = 2'd0;

wire [21:0] c_addr_b = c_addr + {19'd0, c_beat};
wire [1:0]  b_bank = c_addr_b[8:7];
wire [2:0]  b_cb   = {c_chip, c_addr_b[8:7]};          // the row of this chip's bank
wire [12:0] b_row  = c_addr_b[21:9];
wire [8:0]  b_col  = {c_addr_b[6:0], 2'b00};

// a command to the chip of the access (cs_n low), or to both chips (all)
task cmd(input cs_n, input ras_n, input cas_n, input we_n);
	sd_cs  <= cs_n ? 2'b11 : (c_chip ? 2'b01 : 2'b10);
	sd_ras <= ras_n;
	sd_cas <= cas_n;
	sd_we  <= we_n;
endtask
task cmd_all(input ras_n, input cas_n, input we_n);
	sd_cs  <= CHIP1 ? 2'b00 : 2'b10;
	sd_ras <= ras_n;
	sd_cas <= cas_n;
	sd_we  <= we_n;
endtask

integer k;
always @(posedge clk_mem) begin
	cmd(1'b1, 1'b1, 1'b1, 1'b1);
	sd_data_oe <= 1'b0;
	sd_dqm     <= 2'b00;
	if (act_age != 4'd15) act_age <= act_age + 4'd1;
	if (rd_age  != 4'd15) rd_age  <= rd_age + 4'd1;
	if (wr_age  != 4'd15) wr_age  <= wr_age + 4'd1;
	if (cnt != 16'd0) cnt <= cnt - 16'd1;

	// refresh timer
	if (ref_cnt == REFI[11:0] - 12'd1) begin ref_cnt <= 12'd0; ref_due <= 1'b1; end
	else ref_cnt <= ref_cnt + 12'd1;

	// read words
	rp_v <= {1'b0, rp_v[7:1]};   // (a READ sets bits 7:4 below: READs are 4 clocks apart, so they are 0 then)
	if (rp_v[0]) begin
		case (rword)
			2'd0: racc[15:0]  <= sd_in_q;
			2'd1: racc[31:16] <= sd_in_q;
			2'd2: racc[47:32] <= sd_in_q;
			2'd3: begin
				rbuf[m_rc[1:0]] <= {sd_in_q, racc};
				m_rc  <= m_rc + 3'd1;
				c_got <= c_got + 3'd1;
			end
		endcase
		rword <= rword + 2'd1;
	end

	if (reset_mem) begin
		state     <= S_POWER;
		cnt       <= POWERUP[15:0];
		init_done <= 1'b0;
		m_init_r  <= 1'b0;
		row_open  <= 8'd0;
		rp_v      <= 8'd0;
		rword     <= 2'd0;
		sd_dqm    <= 2'b11;
	end
	else case (state)
	S_POWER: begin
		sd_dqm <= 2'b11;
		if (cnt == 16'd0) begin state <= S_INIT; istep <= 4'd0; end
	end

	// PRECHARGE all, two AUTO REFRESH, LOAD MODE
	S_INIT: begin
		sd_dqm <= 2'b11;
		if (cnt == 16'd0) begin
			istep <= istep + 4'd1;
			case (istep)
				4'd0: begin cmd_all(1'b0, 1'b1, 1'b0); sd_addr <= 13'b0_0100_0000_0000; cnt <= T_RP[15:0]; end
				4'd1, 4'd2: begin cmd_all(1'b0, 1'b0, 1'b1); cnt <= T_RFC[15:0]; end
				4'd3: begin cmd_all(1'b0, 1'b0, 1'b0); sd_ba <= 2'b00; sd_addr <= MODE; cnt <= T_MRD[15:0]; end
				default: begin
					state     <= S_IDLE;
					init_done <= 1'b1;
					m_init_r  <= 1'b1;
					ref_cnt   <= 12'd0;
					ref_due   <= 1'b0;
				end
			endcase
		end
	end

	S_IDLE:
		if (ref_due) begin
			// close every row (when allowed), then refresh
			if (row_open != 8'd0) begin
				if (act_age >= T_RAS && wr_age >= T_WR + 3 && rd_age >= 4) begin
					cmd_all(1'b0, 1'b1, 1'b0);
					sd_addr[10] <= 1'b1;
					row_open <= 8'd0;
					cnt <= T_RP[15:0] - 16'd1;
					state <= S_REFRESH;
				end
			end
			else begin
				cnt <= 16'd0;
				state <= S_REFRESH;
			end
		end
		else if (s_req != m_seen) begin
			m_seen  <= s_req;
			c_we    <= s_we;
			c_last  <= s_beats;
			c_addr  <= s_addr;
			c_chip  <= s_chip;
			c_wdata <= s_wdata;
			c_be    <= s_be;
			c_beat  <= 3'd0;
			c_got   <= 3'd0;
			state   <= S_ACCESS;
		end

	S_REFRESH:
		if (cnt == 16'd0) begin
			cmd_all(1'b0, 1'b0, 1'b1);
			ref_due <= 1'b0;
			cnt     <= T_RFC[15:0] - 16'd1;
			state   <= S_WAIT;
		end

	// one beat: open its row, then READ or WRITE
	S_ACCESS:
		if (cnt == 16'd0) begin
			if (row_open[b_cb] && row_of[b_cb] == b_row) begin
				if (c_we) begin
					// no WRITE while read data may be on the bus
					if (rd_age >= 9) begin
						cmd(1'b0, 1'b1, 1'b0, 1'b0);
						sd_ba       <= b_bank;
						sd_addr     <= {4'b0000, b_col};
						sd_data_out <= c_wdata[15:0];
						sd_dqm      <= ~c_be[1:0];
						sd_data_oe  <= 1'b1;
						wr_age      <= 4'd0;
						cnt         <= 16'd3;
						state       <= S_FINISH;
						istep       <= 4'd1;
					end
				end
				else begin
					cmd(1'b0, 1'b1, 1'b0, 1'b1);
					sd_ba   <= b_bank;
					sd_addr <= {4'b0000, b_col};
					rd_age  <= 4'd0;
					rp_v[7:4] <= 4'b1111;
					if (c_beat == c_last) state <= S_RDWAIT;
					else begin
						c_beat <= c_beat + 3'd1;
						cnt    <= 16'd3;        // the next READ 4 clocks on
					end
				end
			end
			else if (row_open[b_cb]) begin
				// another row of the bank: PRECHARGE it
				if (act_age >= T_RAS && wr_age >= T_WR + 3 && rd_age >= 4) begin
					cmd(1'b0, 1'b0, 1'b1, 1'b0);
					sd_ba       <= b_bank;
					sd_addr[10] <= 1'b0;
					row_open[b_cb] <= 1'b0;
					cnt <= T_RP[15:0] - 16'd1;
				end
			end
			else if (act_age >= 2) begin
				cmd(1'b0, 1'b0, 1'b1, 1'b1);
				sd_ba   <= b_bank;
				sd_addr <= b_row;
				row_open[b_cb] <= 1'b1;
				row_of[b_cb]   <= b_row;
				act_age <= 4'd0;
				cnt     <= T_RCD[15:0] - 16'd1;
			end
		end

	// the beat's WRITEs 1..3
	S_FINISH: begin
		if (istep != 4'd4) begin
			cmd(1'b0, 1'b1, 1'b0, 1'b0);
			sd_ba       <= b_bank;
			sd_addr     <= {4'b0000, b_col[8:2], istep[1:0]};
			sd_data_out <= c_wdata[16 * istep +: 16];
			sd_dqm      <= ~c_be[2 * istep +: 2];
			sd_data_oe  <= 1'b1;
			wr_age      <= 4'd0;
			istep       <= istep + 4'd1;
		end
		if (istep == 4'd3) begin
			m_done   <= ~m_done;
			dbg_cmds <= dbg_cmds + 32'd1;
			state    <= S_IDLE;
		end
	end

	S_RDWAIT:
		if (c_got == c_last + 3'd1 && rp_v == 8'd0) begin
			m_done   <= ~m_done;
			dbg_cmds <= dbg_cmds + 32'd1;
			state    <= S_IDLE;
		end

	S_WAIT:
		if (cnt == 16'd0) state <= S_IDLE;

	default: state <= S_IDLE;
	endcase
end

endmodule
