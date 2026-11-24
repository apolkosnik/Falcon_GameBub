//--------------------------------------------------------------------------//
// AP68030 - MC68030 compatible CPU                                         //
//                                                                          //
// ap030_top.v - the processor with the MC68030 pin set (UM Section 5)     //
//                                                                          //
// Bidirectional and three-state pins are presented as separate input,      //
// output and enable signals so the module can be used in simulation and    //
// wrapped for an FPGA's tristate buffers:                                  //
//   D31-D0    d_i / d_o / d_oe                                              //
//   A, FC, SIZ, R/W, RMC, AS, DS, DBEN, CIOUT, CBREQ   driven when bus_oe   //
//   RESET     reset_n_i (input) / reset_n_oe (drive low: RESET instruction) //
// Active-low pins carry the _n suffix.                                     //
//--------------------------------------------------------------------------//

// ---- begin ap030_defs.svh (inlined by tools/import_falcon.py) ----
//--------------------------------------------------------------------------//
// AP68030 - MC68030 compatible CPU                                         //
//                                                                          //
// ap030_defs.svh - constants shared by every module                        //
//                                                                          //
// References are to the MC68030 User's Manual (MC68030UM/AD rev 3) unless  //
// noted: "UM 7.2.1" is section 7.2.1, "PRM" is the M68000 Programmer's     //
// Reference Manual.                                                        //
//--------------------------------------------------------------------------//


// Function codes (UM Table 4-1)
`define FC_USER_DATA   3'd1
`define FC_USER_PROG   3'd2
`define FC_SUPER_DATA  3'd5
`define FC_SUPER_PROG  3'd6
`define FC_CPU_SPACE   3'd7

// SIZ1:SIZ0 pin encoding (UM Table 7-2): bytes remaining in the operand
`define SIZ_LONG   2'b00
`define SIZ_BYTE   2'b01
`define SIZ_WORD   2'b10
`define SIZ_3BYTE  2'b11

// Port size as reported by DSACK1:DSACK0 (UM Table 7-1) or STERM
`define PORT_8    2'd0
`define PORT_16   2'd1
`define PORT_32   2'd2

// Internal operand sizes
`define SZ_B  2'd0
`define SZ_W  2'd1
`define SZ_L  2'd2
`define SZ_3  2'd3   // three bytes: the rerun of a faulted second portion (UM 8.2.1 SIZE)

// SR bits
`define SR_C   0
`define SR_V   1
`define SR_Z   2
`define SR_N   3
`define SR_X   4
`define SR_M   12
`define SR_S   13
`define SR_T0  14
`define SR_T1  15
`define SR_RESET  16'h2700
`define SR_MASK   16'hF71F
`define CCR_MASK  16'h001F

// Exception vectors (UM Table 8-1)
`define VEC_BUSERR    8'd2
`define VEC_ADDRERR   8'd3
`define VEC_ILLEGAL   8'd4
`define VEC_DIVZERO   8'd5
`define VEC_CHK       8'd6
`define VEC_TRAPCC    8'd7
`define VEC_PRIV      8'd8
`define VEC_TRACE     8'd9
`define VEC_ALINE     8'd10
`define VEC_FLINE     8'd11
`define VEC_CPPROTO   8'd13
`define VEC_FMTERR    8'd14
`define VEC_UNINIT    8'd15
`define VEC_SPURIOUS  8'd24
`define VEC_AUTOVEC   8'd24   // + level
`define VEC_TRAP      8'd32   // + n
`define VEC_MMUCONF   8'd56

// Exception stack frame formats (UM 8.4)
`define FMT_NORMAL    4'h0
`define FMT_THROWAWAY 4'h1
`define FMT_SIXWORD   4'h2
`define FMT_CPMID     4'h9
`define FMT_SHORTBUS  4'hA
`define FMT_LONGBUS   4'hB

// CACR bits (UM Figure 6-14)
`define CACR_EI   0
`define CACR_FI   1
`define CACR_CEI  2
`define CACR_CI   3
`define CACR_IBE  4
`define CACR_ED   8
`define CACR_FD   9
`define CACR_CED  10
`define CACR_CD   11
`define CACR_DBE  12
`define CACR_WA   13
`define CACR_MASK 32'h0000_3F1F   // bits that are stored (CD/CED/CI/CEI read as zero)
`define CACR_RDMASK 32'h0000_3313

// MMU status register (UM Figure 9-38)
`define MMUSR_B   15
`define MMUSR_L   14
`define MMUSR_S   13
`define MMUSR_W   11
`define MMUSR_I   10
`define MMUSR_M   9
`define MMUSR_T   6
// bits 2:0 = N

// ALU operations
`define ALU_MOVE   6'd0
`define ALU_ADD    6'd1
`define ALU_ADDX   6'd2
`define ALU_SUB    6'd3
`define ALU_SUBX   6'd4
`define ALU_CMP    6'd5
`define ALU_AND    6'd6
`define ALU_OR     6'd7
`define ALU_EOR    6'd8
`define ALU_NOT    6'd9
`define ALU_NEG    6'd10
`define ALU_NEGX   6'd11
`define ALU_CLR    6'd12
`define ALU_TST    6'd13
`define ALU_EXT    6'd14
`define ALU_EXTB   6'd15
`define ALU_SWAP   6'd16
`define ALU_TAS    6'd17
`define ALU_ABCD   6'd18
`define ALU_SBCD   6'd19
`define ALU_NBCD   6'd20
`define ALU_ASL    6'd21
`define ALU_ASR    6'd22
`define ALU_LSL    6'd23
`define ALU_LSR    6'd24
`define ALU_ROL    6'd25
`define ALU_ROR    6'd26
`define ALU_ROXL   6'd27
`define ALU_ROXR   6'd28
`define ALU_BTST   6'd29
`define ALU_BCHG   6'd30
`define ALU_BCLR   6'd31
`define ALU_BSET   6'd32
`define ALU_MOVEB  6'd33   // MOVE: flags from source, no X (same as MOVE)
`define ALU_SUBA   6'd34   // address arithmetic: no flags
`define ALU_ADDA   6'd35
`define ALU_MOVEA  6'd36
`define ALU_CMPA   6'd37   // CMPA: operands sign-extended to 32 by the core; long compare
`define ALU_PASSB  6'd38   // result = b, flags unchanged

// Bus controller transaction kinds
`define BK_DATA  2'd0   // ordinary operand / prefetch transfer
`define BK_IACK  2'd1   // interrupt acknowledge (AVEC honoured, vector on low port byte)
`define BK_TABLE 2'd2   // MMU table search (RMC asserted by the requester)

// ---- end ap030_defs.svh ----

module ap030_top
#(
	// PC-relative operand reads use program space (UM 2.4, 4.2).  An
	// integration whose glue reads "program space" as "instruction fetch"
	// (a TG68-style busstate, as Minimig's cpu_wrapper) sets this to 0 so
	// those reads keep the data function code there.
	parameter PCREL_PROGRAM_SPACE = 1,
	parameter FAST_PORT = 0,
	// USE_CE = 1: the processor clock is clk gated by ce (a clock enable in
	// the clk domain): the core advances on the rising edges of clk with ce
	// set and on the falling edge that follows each of them, so ce every
	// second clk runs it at half the clk rate, every fourth at a quarter.
	// USE_CE = 0: ce is not used (every edge, as before).
	parameter USE_CE = 0
)
(
	input             clk,
	input             ce,

	// bus
	output     [31:0] a,
	output      [2:0] fc,
	output      [1:0] siz,
	output            rw,
	output            rmc_n,
	output            as_n,
	output            ds_n,
	output            dben_n,
	output            ecs_n,
	output            ocs_n,
	output            ciout_n,
	output            cbreq_n,
	output            bus_oe,
	output     [31:0] d_o,
	output            d_oe,
	input      [31:0] d_i,
	input             dsack0_n,
	input             dsack1_n,
	input             sterm_n,
	input             berr_n,
	input             halt_n,
	input             avec_n,
	input             ciin_n,
	input             cback_n,
	input             br_n,
	output            bg_n,
	input             bgack_n,
	// interrupts
	input       [2:0] ipl_n,
	output            ipend_n,
	// reset (open drain: input from the pin, output enable drives it low)
	input             reset_n_i,
	output            reset_n_oe,
	// emulator support
	input             cdis_n,
	input             mmudis_n,
	output            refill_n,
	output            status_n,

	// Optional internal Fast RAM port, after translation. Request fields
	// remain stable through fast_req && fast_ready. Responses have no
	// backpressure: first word completes the operand, fast_last releases
	// the slot; further words are wrapped cache-line fill beats.
	// Address is physical; bit 3 of fast_be selects fast_wdata[31:24].
	// Replies begin at least one clock after acceptance. The target must
	// complete without BERR; potentially faulting/locked transfers use pins.
	output            fast_req,
	output     [31:0] fast_addr,
	output      [2:0] fast_fc,
	output            fast_rw, fast_ci, fast_burst,
	output      [3:0] fast_be,
	output     [31:0] fast_wdata,
	input             fast_match, fast_ready,
	input             fast_valid, fast_last,
	input       [1:0] fast_word,
	input      [31:0] fast_rdata,

	// observation
	output     [31:0] dbg_pc,
	output     [15:0] dbg_sr,
	output      [7:0] dbg_state,
	output            dbg_inst,
	// timing hooks (ap030_core): instruction words taken from the prefetch
	// queue, and a word-size multiply/divide started (1 MUL.W, 2 DIVU.W,
	// 3 DIVS.W), each for one processor clock
	output      [1:0] tm_pop,
	output      [1:0] tm_md,
	// the prefetch queue, for an external pipeline model, and that model's
	// limits on the next fetches (ap030_core; used with fetch_lazy only, tie
	// the inputs to 0 without a model): tm_q holds tm_qn queued words, word
	// 0 (the next to take, at address tm_scan) in [95:80]; tm_flush: the
	// queue was flushed or reloaded (branch, exception) in the last clock.
	// fetch_stop_v/fetch_stop: no longword is fetched once the next word to
	// take, at the consumption that made the fetch due, is at fetch_stop - 2
	// or beyond; fetch_scan_v/fetch_scan_to (the first word not yet
	// scanned): while the model scans, a fetch waits until it has scanned
	// the words below that word + 4 (or below the longword it wants).  When
	// the processor has waited 63 clocks for an instruction word that is
	// neither queued nor on the way, the stop and the scan wait are ignored,
	// so wrong model inputs cannot hang it (a stop holding while the
	// processor still has the words it needs is not affected).
	output     [95:0] tm_q,
	output      [2:0] tm_qn,
	output     [31:0] tm_scan,
	output            tm_flush,
	input             fetch_stop_v,
	input      [31:0] fetch_stop,
	input             fetch_scan_v,
	input      [31:0] fetch_scan_to,
	output            dbg_halted,
	// system glue (emulator integration): VBR, CACR, cache-clear pulses
	output     [31:0] dbg_vbr,
	output     [31:0] dbg_cacr,
	output            dbg_cache_clear,  // pulse: CACR written with CD, CED, CI or CEI set
	// system options (tie to 0 for a plain MC68030):
	//  snoop_we/snoop_addr: another bus master wrote this address; the data
	//    cache entry for it is invalidated (the MC68030 has no snooping --
	//    this is glue for systems whose DMA writes cachable-by-allocation RAM)
	//  nmi_vec_nocache: the level 7 autovector fetch bypasses the data cache
	//  fetch_lazy: instruction prefetch as Hatari's 68030 model: a longword
	//    is fetched only when two words or fewer are left (queued or on the
	//    way) after the words taken in a clock, instead of four; after a
	//    branch that fetches the target's longword and the next one (and a
	//    third for a target at an odd word), as Hatari's three-word queue
	//    does (get_word_ce030_prefetch, fill_prefetch_030_ntx)
	input             snoop_we,
	input      [31:0] snoop_addr,
	input             nmi_vec_nocache,
	input             fetch_lazy
);

//---------------------------------------------------------------------------
// reset: the pin is synchronized; while the RESET instruction drives it the
// processor ignores it, and an external assertion must outlast that by
// eight clocks to reset the processor (UM 7.8)
//---------------------------------------------------------------------------
// the clock enables: rising edges with ce, the falling edge after each of them
wire       ce_r = (USE_CE != 0) ? ce : 1'b1;
reg        ce_f = 1'b1;
always @(posedge clk) ce_f <= ce_r;

reg  [1:0] rst_sync;
reg  [3:0] rst_cnt;
reg        rst;
wire       reset_drive;
always @(posedge clk) if (ce_r) begin
	rst_sync <= {rst_sync[0], ~reset_n_i};
	if (reset_drive) begin rst_cnt <= 4'd0; end
	else if (rst_sync[1]) begin if (rst_cnt != 4'd15) rst_cnt <= rst_cnt + 4'd1; end
	else rst_cnt <= 4'd0;
	rst <= rst_sync[1] && !reset_drive && (rst_cnt >= 4'd7 || rst);
end
initial begin rst_sync = 2'b11; rst_cnt = 4'd15; rst = 1'b1; end
assign reset_n_oe = reset_drive;

// synchronized emulator inputs
reg cdis_s, mmudis_s;
always @(posedge clk) if (ce_r) begin cdis_s <= ~cdis_n; mmudis_s <= ~mmudis_n; end

//---------------------------------------------------------------------------
// core <-> memory subsystem
//---------------------------------------------------------------------------
wire        d_stb, d_rw, d_rmc, d_rmc_last, d_rmc_release, d_iack, d_nocache;
wire [31:0] d_addr, d_wdata, d_rdata;
wire  [1:0] d_size;
wire  [2:0] d_fc;
wire        d_ack, d_fault, d_avec, d_iack_berr, d_late_fault, d_wpend, d_held, d_cancel, d_unhold;
wire [31:0] f_addr, f_dob, f_partial;
wire  [2:0] f_fc, f_got;
wire  [1:0] f_size;
wire        f_rw, f_rm;
wire        i_stb, i_ack, i_fault, i_ready;
wire [31:0] i_addr, i_data;
wire  [2:0] i_fc;
wire        op_req, op_done, reg_we, reg_fd, cfg_err, bus_quiet;
wire  [2:0] op_kind, op_level, op_fc, op_fcmask, reg_sel;
wire [31:0] op_la, op_desc_addr, reg_wdata_hi, reg_wdata_lo;
wire [31:0] tc, srp_hi, srp_lo, crp_hi, crp_lo, tt0, tt1;
wire [15:0] mmusr;
wire [31:0] cacr;
wire        cacr_ci, cacr_cei, cacr_cd, cacr_ced;
assign dbg_cacr = cacr;
assign dbg_cache_clear = cacr_ci | cacr_cd | cacr_cei | cacr_ced;
wire  [7:2] caar_idx;
wire        halted;

ap030_core #(.PCREL_PROGRAM_SPACE(PCREL_PROGRAM_SPACE)) core (
	.clk(clk), .ce(ce_r), .ce_f(ce_f), .rst(rst),
	.d_stb(d_stb), .d_addr(d_addr), .d_size(d_size), .d_rw(d_rw), .d_rmc(d_rmc), .d_rmc_last(d_rmc_last),
	.d_rmc_release(d_rmc_release), .d_iack(d_iack), .d_nocache(d_nocache), .d_fc(d_fc), .d_wdata(d_wdata),
	.d_ack(d_ack), .d_rdata(d_rdata), .d_fault(d_fault), .d_avec(d_avec), .d_iack_berr(d_iack_berr),
	.d_late_fault(d_late_fault), .d_wpend(d_wpend), .d_held(d_held), .d_cancel(d_cancel), .d_unhold(d_unhold),
	.f_addr(f_addr), .f_fc(f_fc), .f_size(f_size), .f_rw(f_rw), .f_rm(f_rm), .f_dob(f_dob),
	.f_got(f_got), .f_partial(f_partial),
	.i_stb(i_stb), .i_addr(i_addr), .i_fc(i_fc), .i_ready(i_ready), .i_ack(i_ack), .i_data(i_data), .i_fault(i_fault),
	.op_req(op_req), .op_kind(op_kind), .op_level(op_level), .op_la(op_la), .op_fc(op_fc), .op_fcmask(op_fcmask),
	.op_done(op_done), .op_desc_addr(op_desc_addr),
	.reg_we(reg_we), .reg_sel(reg_sel), .reg_wdata_hi(reg_wdata_hi), .reg_wdata_lo(reg_wdata_lo), .reg_fd(reg_fd),
	.cfg_err(cfg_err), .tc(tc), .srp_hi(srp_hi), .srp_lo(srp_lo), .crp_hi(crp_hi), .crp_lo(crp_lo),
	.tt0(tt0), .tt1(tt1), .mmusr(mmusr), .bus_quiet(bus_quiet),
	.cacr(cacr), .cacr_ci(cacr_ci), .cacr_cei(cacr_cei), .cacr_cd(cacr_cd), .cacr_ced(cacr_ced), .caar_idx(caar_idx),
	.ipl_n(ipl_n), .ipend_n(ipend_n), .reset_drive(reset_drive), .status_n(status_n), .refill_n(refill_n),
	.halted(halted), .dbg_pc(dbg_pc), .dbg_sr(dbg_sr), .dbg_state(dbg_state), .dbg_inst(dbg_inst), .tm_pop(tm_pop), .tm_md(tm_md),
	.tm_q(tm_q), .tm_qn(tm_qn), .tm_scan(tm_scan), .tm_flush(tm_flush),
	.fetch_stop_v(fetch_stop_v), .fetch_stop(fetch_stop),
	.fetch_scan_v(fetch_scan_v), .fetch_scan_to(fetch_scan_to),
	.dbg_vbr(dbg_vbr)
,
	.nmi_vec_nocache(nmi_vec_nocache), .fetch_lazy(fetch_lazy)
);

ap030_memsys #(.FAST_PORT(FAST_PORT)) memsys (
	.clk(clk), .ce(ce_r), .ce_f(ce_f), .rst(rst),
	.cacr(cacr), .cacr_ci(cacr_ci), .cacr_cei(cacr_cei), .cacr_cd(cacr_cd), .cacr_ced(cacr_ced),
	.caar_idx(caar_idx), .cdis(cdis_s), .mmudis(mmudis_s), .halted(halted),
	.d_stb(d_stb), .d_addr(d_addr), .d_size(d_size), .d_rw(d_rw), .d_rmc(d_rmc), .d_rmc_last(d_rmc_last),
	.d_rmc_release(d_rmc_release), .d_iack(d_iack), .d_nocache(d_nocache), .snoop_we(snoop_we), .snoop_addr(snoop_addr), .d_fc(d_fc), .d_wdata(d_wdata),
	.d_ack(d_ack), .d_rdata(d_rdata), .d_fault(d_fault), .d_avec(d_avec), .d_iack_berr(d_iack_berr),
	.d_late_fault(d_late_fault), .d_wpend(d_wpend), .d_held(d_held), .d_cancel(d_cancel), .d_unhold(d_unhold),
	.f_addr(f_addr), .f_fc(f_fc), .f_size(f_size), .f_rw(f_rw), .f_rm(f_rm), .f_dob(f_dob),
	.f_got(f_got), .f_partial(f_partial),
	.i_stb(i_stb), .i_addr(i_addr), .i_fc(i_fc), .i_ready(i_ready), .i_ack(i_ack), .i_data(i_data), .i_fault(i_fault),
	.op_req(op_req), .op_kind(op_kind), .op_level(op_level), .op_la(op_la), .op_fc(op_fc), .op_fcmask(op_fcmask),
	.op_done(op_done), .op_desc_addr(op_desc_addr),
	.reg_we(reg_we), .reg_sel(reg_sel), .reg_wdata_hi(reg_wdata_hi), .reg_wdata_lo(reg_wdata_lo), .reg_fd(reg_fd),
	.cfg_err(cfg_err), .tc(tc), .srp_hi(srp_hi), .srp_lo(srp_lo), .crp_hi(crp_hi), .crp_lo(crp_lo),
	.tt0(tt0), .tt1(tt1), .mmusr(mmusr), .bus_quiet(bus_quiet),
	.a_o(a), .fc_o(fc), .siz_o(siz), .rw_o(rw), .rmc_n_o(rmc_n), .as_n_o(as_n), .ds_n_o(ds_n), .dben_n_o(dben_n),
	.ecs_n_o(ecs_n), .ocs_n_o(ocs_n), .ciout_n_o(ciout_n), .cbreq_n_o(cbreq_n), .bus_oe(bus_oe),
	.d_o(d_o), .d_oe(d_oe), .d_i(d_i),
	.dsack0_n(dsack0_n), .dsack1_n(dsack1_n), .sterm_n(sterm_n), .berr_n(berr_n), .halt_n(halt_n),
	.avec_n(avec_n), .ciin_n(ciin_n), .cback_n(cback_n), .br_n(br_n), .bgack_n(bgack_n),
	.bg_n_o(bg_n), .bus_granted(),
	.fast_req(fast_req), .fast_addr(fast_addr), .fast_fc(fast_fc), .fast_rw(fast_rw),
	.fast_ci(fast_ci), .fast_burst(fast_burst), .fast_be(fast_be), .fast_wdata(fast_wdata),
	.fast_match(fast_match), .fast_ready(fast_ready), .fast_valid(fast_valid),
	.fast_last(fast_last), .fast_word(fast_word), .fast_rdata(fast_rdata)
);

assign dbg_halted = halted;

endmodule
