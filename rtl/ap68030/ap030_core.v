//--------------------------------------------------------------------------//
// AP68030 - MC68030 compatible CPU                                         //
//                                                                          //
// ap030_core.v - execution unit: instruction pipe, decoder, sequencer,     //
// exception processing, coprocessor interface, MMU instructions            //
//                                                                          //
// The sequencer is a state machine whose states are in core/ap030_states   //
// .vh and whose bodies are in the core/ap030_*.vh includes.  Every data    //
// access goes through one wait state (S_DWAIT) with a recorded destination //
// and return state, which is also what makes an instruction resumable      //
// after a bus fault: the format $B frame carries the resume state and the  //
// temporaries, RTE restores them (UM 8.2, 8.4).                            //
//                                                                          //
// The instruction pipe holds up to six words; the first two are the        //
// MC68030's stages C and B for the fault frames, so stage C = the word at  //
// scan_pc and stage B = the word at scan_pc + 2 (UM 8.2).                  //
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

module ap030_core
#(
	parameter PCREL_PROGRAM_SPACE = 1   // see ap030_top
)
(
	input             clk,
	input             ce,          // clock enable: the core advances on enabled rising edges
	input             ce_f,        // ... and on the falling edge after an enabled rising edge
	input             rst,

	// ---- data port (ap030_memsys) ---------------------------------------
	output reg        d_stb,
	output reg [31:0] d_addr,
	output reg  [1:0] d_size,
	output reg        d_rw,
	output reg        d_rmc,
	output reg        d_rmc_last,
	output reg        d_rmc_release,
	output reg        d_iack,
	output reg        d_nocache,    // this read bypasses the data cache (system option, see ap030_top)
	input             nmi_vec_nocache,
	input             fetch_lazy,   // prefetch as Hatari's 68030 model (see ap030_top)
	output reg  [2:0] d_fc,
	output reg [31:0] d_wdata,
	input             d_ack,
	input      [31:0] d_rdata,
	input             d_fault,
	input             d_avec,
	input             d_iack_berr,
	input             d_late_fault,
	input             d_wpend,
	input             d_held,       // the access waits behind a posted write fault
	output reg        d_cancel,     // pulse: drop it (the instruction is suspended)
	output reg        d_unhold,     // pulse: let it go
	input      [31:0] f_addr,
	input       [2:0] f_fc,
	input       [1:0] f_size,
	input             f_rw,
	input             f_rm,
	input      [31:0] f_dob,
	input       [2:0] f_got,
	input      [31:0] f_partial,

	// ---- instruction port ------------------------------------------------
	output reg        i_stb,
	(* dont_retime *) output reg [31:0] i_addr,
	output reg  [2:0] i_fc,
	input             i_ready,      // the memory system can take another fetch
	input             i_ack,
	input      [31:0] i_data,
	input             i_fault,

	// ---- MMU instructions and registers --------------------------------
	output reg        op_req,
	output reg  [2:0] op_kind,
	output reg  [2:0] op_level,
	output reg [31:0] op_la,
	output reg  [2:0] op_fc,
	output reg  [2:0] op_fcmask,
	input             op_done,
	input      [31:0] op_desc_addr,
	output reg        reg_we,
	output reg  [2:0] reg_sel,
	output reg [31:0] reg_wdata_hi,
	output reg [31:0] reg_wdata_lo,
	output reg        reg_fd,
	input             cfg_err,
	input      [31:0] tc,
	input      [31:0] srp_hi, srp_lo, crp_hi, crp_lo,
	input      [31:0] tt0, tt1,
	input      [15:0] mmusr,
	input             bus_quiet,

	// ---- cache control -----------------------------------------------------
	output reg [31:0] cacr,
	output reg        cacr_ci,
	output reg        cacr_cei,
	output reg        cacr_cd,
	output reg        cacr_ced,
	output      [7:2] caar_idx,

	// ---- pins --------------------------------------------------------------
	input       [2:0] ipl_n,
	output            ipend_n,
	output reg        reset_drive,   // RESET instruction: drive the RESET pin low
	output            status_n,
	output            refill_n,
	output            halted,

	output     [31:0] dbg_pc,
	output     [15:0] dbg_sr,
	output      [7:0] dbg_state,
	output reg        dbg_inst,     // pulse: an instruction was dispatched (statistics)
	// timing hooks for an external timing model (one processor clock each):
	// instruction words taken from the prefetch queue; a word-size
	// multiply/divide started (1 MULU.W/MULS.W, 2 DIVU.W, 3 DIVS.W)
	output reg  [1:0] tm_pop,
	output reg  [1:0] tm_md,
	// the prefetch queue for an external pipeline model (words from scan_pc
	// on; valid count; a flush or reload of the queue in the last clock),
	// and that model's stop point: with fetch_lazy no longword is fetched
	// once the next word to take is at fetch_stop - 2 or beyond
	output     [95:0] tm_q,
	output      [2:0] tm_qn,
	output     [31:0] tm_scan,
	output reg        tm_flush,
	input             fetch_stop_v,
	input      [31:0] fetch_stop,
	input             fetch_scan_v,  // the model is scanning: wait until it has passed
	input      [31:0] fetch_scan_to, //   the word two ahead (or the words below the fetch)
	output     [31:0] dbg_vbr       // VBR (system glue: NMI vector address)
);

// ---- begin core/ap030_states.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - sequencer states (included by ap030_core.v)
localparam S_RESET0    = 8'd0;
localparam S_RESET1    = 8'd1;
localparam S_RESET2    = 8'd2;
localparam S_FETCH     = 8'd3;    // instruction boundary
localparam S_STOPPED   = 8'd4;
localparam S_HALT      = 8'd5;    // double bus fault
localparam S_DWAIT     = 8'd6;    // waiting for the data port
localparam S_IMM       = 8'd7;    // immediate operand from the instruction stream
localparam S_EA        = 8'd8;    // effective address calculation
localparam S_EA_FULL   = 8'd9;    // full extension word: base displacement
localparam S_EA_IND    = 8'd10;   // memory indirect: intermediate address read done
localparam S_EA_OD     = 8'd11;   // outer displacement
localparam S_GEN_RD    = 8'd12;   // read the memory operand
localparam S_GEN_EXEC  = 8'd13;   // ALU and write back
localparam S_MOVE_DEA  = 8'd14;   // MOVE: destination EA
localparam S_MOVE_WR   = 8'd15;   // MOVE: write
localparam S_LEA       = 8'd16;
localparam S_PEA       = 8'd17;
localparam S_BCC       = 8'd18;
localparam S_BCC_DISP  = 8'd19;
localparam S_JMP       = 8'd20;
localparam S_JSR       = 8'd21;
localparam S_RTS       = 8'd22;
localparam S_RTS2      = 8'd23;
localparam S_RTR       = 8'd24;
localparam S_RTD       = 8'd25;
localparam S_DBCC      = 8'd26;
localparam S_SCC       = 8'd27;
localparam S_TRAPCC    = 8'd28;
localparam S_MOVEM0    = 8'd29;
localparam S_MOVEM1    = 8'd30;
localparam S_MOVEM2    = 8'd31;
localparam S_MOVEM3    = 8'd32;
localparam S_MULDIV0   = 8'd33;
localparam S_MULDIV1   = 8'd34;
localparam S_MULDIV2   = 8'd35;
localparam S_MULDIVW   = 8'd36;
localparam S_LINK      = 8'd37;
localparam S_LINK2     = 8'd38;
localparam S_UNLK      = 8'd39;
localparam S_UNLK2     = 8'd40;
localparam S_MOVEP0    = 8'd41;
localparam S_MOVEP1    = 8'd42;
localparam S_MOVEP2    = 8'd43;
localparam S_CHK       = 8'd44;
localparam S_CHK2_0    = 8'd45;
localparam S_CHK2_1    = 8'd46;
localparam S_CHK2_2    = 8'd47;
localparam S_CAS0      = 8'd48;
localparam S_CAS1      = 8'd49;
localparam S_CAS2_0    = 8'd50;
localparam S_CAS2_1    = 8'd51;
localparam S_CAS2_2    = 8'd52;
localparam S_CAS2_3    = 8'd53;
localparam S_CAS2_4    = 8'd54;
localparam S_BF0       = 8'd55;
localparam S_BF1       = 8'd56;
localparam S_BF2       = 8'd57;
localparam S_BF3       = 8'd58;
localparam S_BF4       = 8'd59;
localparam S_MOVE_SR   = 8'd60;   // MOVE to SR/CCR, ORI/ANDI/EORI to SR/CCR
localparam S_MOVE_FSR  = 8'd61;   // MOVE from SR/CCR
localparam S_MOVEC     = 8'd62;
localparam S_MOVES0    = 8'd63;
localparam S_MOVES1    = 8'd64;
localparam S_STOP      = 8'd65;
localparam S_RESETI    = 8'd66;   // RESET instruction
localparam S_TRAP      = 8'd67;
localparam S_EXG       = 8'd68;
localparam S_PACK      = 8'd69;
localparam S_PACK2     = 8'd70;
localparam S_BKPT      = 8'd71;
localparam S_BKPT2     = 8'd72;
localparam S_SHIFT     = 8'd73;
localparam S_EXC0      = 8'd74;   // exception: SR update, stack selection
localparam S_EXC1      = 8'd75;   // frame push loop
localparam S_EXC2      = 8'd76;   // vector fetch
localparam S_EXC3      = 8'd77;   // throwaway frame (M bit) or finish
localparam S_EXC4      = 8'd78;
localparam S_IACK      = 8'd79;
localparam S_RTE0      = 8'd80;
localparam S_RTE1      = 8'd81;
localparam S_RTE2      = 8'd82;
localparam S_RTE3      = 8'd83;
localparam S_RTE4      = 8'd84;
localparam S_RTE5      = 8'd85;
localparam S_RTE_RERUN = 8'd86;
localparam S_CP0       = 8'd87;   // coprocessor: write command/condition
localparam S_CP1       = 8'd88;   // read response
localparam S_CP2       = 8'd89;   // dispatch primitive
localparam S_CP3       = 8'd90;
localparam S_CP4       = 8'd91;
localparam S_CP5       = 8'd92;
localparam S_CP6       = 8'd93;
localparam S_CP7       = 8'd94;
localparam S_CP8       = 8'd95;
localparam S_CPSAVE0   = 8'd96;
localparam S_CPSAVE1   = 8'd97;
localparam S_CPSAVE2   = 8'd98;
localparam S_CPREST0   = 8'd99;
localparam S_CPREST1   = 8'd100;
localparam S_CPREST2   = 8'd101;
localparam S_CPREST3   = 8'd102;
localparam S_CPBCC     = 8'd103;
localparam S_CPDBCC    = 8'd104;
localparam S_CPSCC     = 8'd105;
localparam S_CPTRAP    = 8'd106;
localparam S_PMMU0     = 8'd107;  // MMU instruction: decode the second word
localparam S_PMOVE_RD  = 8'd108;
localparam S_PMOVE_RD2 = 8'd109;
localparam S_PMOVE_WR  = 8'd110;
localparam S_PMOVE_WR2 = 8'd111;
localparam S_PMOVE_FIN = 8'd112;
localparam S_PFLUSH    = 8'd113;
localparam S_PTEST     = 8'd114;
localparam S_PTEST2    = 8'd115;
localparam S_TAS       = 8'd116;
localparam S_TAS2      = 8'd117;
localparam S_CPXFER    = 8'd118;  // coprocessor: block transfer loop
localparam S_CPXFER2   = 8'd119;
localparam S_CPREGS    = 8'd120;  // transfer multiple main processor registers
localparam S_CPREGS2   = 8'd121;
localparam S_CPMULT    = 8'd122;  // transfer multiple coprocessor registers
localparam S_CPMULT2   = 8'd123;
localparam S_CPMULT3   = 8'd124;
localparam S_EXC_TRACE = 8'd125;
localparam S_MOVE_USP  = 8'd126;
localparam S_NOP       = 8'd127;
localparam S_DIVZ      = 8'd128;
localparam S_CP_ABORT  = 8'd129;
localparam S_CP_EXC    = 8'd130;
localparam S_CPSR      = 8'd131;
localparam S_CPSR2     = 8'd132;
localparam S_CPCTRL    = 8'd133;
localparam S_CPCTRL2   = 8'd134;
localparam S_MOVEM_DEC = 8'd135;
localparam S_EA_DONE   = 8'd136;
localparam S_IMM_DONE  = 8'd137;
localparam S_MOVEM_LAST= 8'd138;
localparam S_BFWR      = 8'd139;
localparam S_CAS_WR    = 8'd140;
localparam S_CPTOS     = 8'd141;
localparam S_CPEAX     = 8'd142;
localparam S_RESUME    = 8'd143;
localparam S_CPBCC2    = 8'd144;
localparam S_CPDBCC2   = 8'd145;
localparam S_RTE_A     = 8'd146;
localparam S_RTE_B     = 8'd147;
localparam S_RTE_PIPE  = 8'd148;
localparam S_CHK2_3    = 8'd149;
localparam S_CP_ISTREAM= 8'd150;

// data-wait destinations
localparam DW_NONE = 4'd0;
localparam DW_SRC  = 4'd1;
localparam DW_DST  = 4'd2;
localparam DW_TMP  = 4'd3;
localparam DW_TMP2 = 4'd4;
localparam DW_EA   = 4'd5;
localparam DW_IMM  = 4'd6;
localparam DW_REG  = 4'd7;    // register dw_reg, merged by d_size
localparam DW_REGL = 4'd8;    // register dw_reg, sign extended to long
localparam DW_SR   = 4'd9;    // low word to SR (RTE/RTR)
localparam DW_PC   = 4'd10;   // new PC (RTS)
localparam DW_FRAME= 4'd11;   // RTE frame array element fr[cnt]

// exception resume kinds ($B frame internal word)
localparam RK_BOUNDARY = 4'd0;
localparam RK_STREAM   = 4'd1;
localparam RK_READ     = 4'd2;
localparam RK_WRITE    = 4'd3;
localparam RK_RMW      = 4'd4;
localparam RK_HELD     = 4'd5;    // suspended at an access behind a posted write fault
localparam S_RTR2      = 8'd151;
localparam S_RTD2      = 8'd152;
localparam S_LINK3     = 8'd153;
localparam S_UNLK3     = 8'd154;
localparam S_EXG2      = 8'd155;
localparam S_PACK3     = 8'd156;
localparam S_TRAPCC2   = 8'd157;
localparam S_MOVEM4    = 8'd158;
localparam S_BF5       = 8'd159;
localparam S_CP9       = 8'd160;
localparam S_CPXFER3   = 8'd161;
localparam S_CHK2_4    = 8'd162;
localparam S_PMOVE_RD3 = 8'd163;
localparam S_EXC5      = 8'd164;
localparam S_MOVEP3    = 8'd165;
localparam S_CP10      = 8'd166;
localparam S_CPREST4   = 8'd167;
localparam S_CPSAVE3   = 8'd168;
localparam S_CAS2_5    = 8'd169;
localparam S_CAS2_6    = 8'd170;
localparam S_CAS2_7    = 8'd171;
localparam S_CAS2_8    = 8'd172;
localparam S_CPSCC2    = 8'd173;
localparam S_CPBUSY    = 8'd174;
localparam S_CPNULL    = 8'd175;
localparam S_CPXEA     = 8'd176;
localparam S_CPXEA2    = 8'd177;
localparam S_CPREG     = 8'd178;
localparam S_CPTOS2    = 8'd179;
localparam S_CPSR3     = 8'd180;
localparam S_CPSAVE4   = 8'd181;
localparam S_CPREST5   = 8'd182;
localparam S_PLOAD     = 8'd183;
localparam S_CPMULT4   = 8'd184;
localparam S_CPWAIT    = 8'd185;
localparam S_CPSV_BODY = 8'd186;
localparam S_CPSV_WR   = 8'd187;
localparam S_CPRS_BODY = 8'd188;
localparam S_CPRS_WR   = 8'd189;
localparam S_CPTRAP2   = 8'd190;
localparam S_CPSCC_WR  = 8'd191;
localparam S_CAS1B    = 8'd192;  // CAS: decide on the registered compare
localparam S_CAS2_4B  = 8'd193;
localparam S_CAS2_5B  = 8'd194;
localparam S_PFLUSH2   = 8'd195;  // PFLUSH fc,#mask,<ea>: the EA is ready
localparam S_EXCW      = 8'd196;  // bus/address error: the posted writes before it complete
localparam S_RTE_HELD  = 8'd197;  // RTE: issue the access the instruction was suspended at
// ---- end core/ap030_states.vh ----

//---------------------------------------------------------------------------
// architectural state
//---------------------------------------------------------------------------
reg [15:0] sr;
reg [31:0] vbr;
assign dbg_vbr = vbr;
reg [31:0] caar;
reg  [2:0] sfc, dfc;
wire       sr_s = sr[`SR_S];
wire       sr_m = sr[`SR_M];
wire [2:0] fc_data = sr_s ? `FC_SUPER_DATA : `FC_USER_DATA;
wire [2:0] fc_prog = sr_s ? `FC_SUPER_PROG : `FC_USER_PROG;
assign caar_idx = caar[7:2];

//---------------------------------------------------------------------------
// register file
//---------------------------------------------------------------------------
reg         rf_we;
reg   [3:0] rf_waddr;
reg   [1:0] rf_wact;           // A7 at issue: 0 USP, 1 ISP, 2 MSP
reg  [31:0] rf_wdata;
reg   [3:0] ra_a, ra_b, ra_c;
wire [31:0] rf_a, rf_b, rf_c;
wire  [3:0] ra_d, ra_e;        // dispatch ports: source and destination registers of the next instruction
wire [31:0] rf_d, rf_e;
reg         sp_we;
reg   [1:0] sp_sel;
reg  [31:0] sp_wdata;
wire [31:0] usp_q, isp_q, msp_q;

ap030_regfile rf (
	.clk(clk), .ce(ce), .rst(rst), .sr_s(sr_s), .sr_m(sr_m),
	.we(rf_we), .waddr(rf_waddr), .wact(rf_wact), .wdata(rf_wdata),
	.raddr_a(ra_a), .rdata_a(rf_a), .raddr_b(ra_b), .rdata_b(rf_b), .raddr_c(ra_c), .rdata_c(rf_c),
	.raddr_d(ra_d), .rdata_d(rf_d), .raddr_e(ra_e), .rdata_e(rf_e),
	.sp_we(sp_we), .sp_sel(sp_sel), .sp_wdata(sp_wdata),
	.usp_q(usp_q), .isp_q(isp_q), .msp_q(msp_q)
);

//---------------------------------------------------------------------------
// ALU and multiply/divide
//---------------------------------------------------------------------------
reg   [5:0] alu_op;
reg   [1:0] alu_size;
reg   [5:0] alu_cnt;
reg  [31:0] alu_a, alu_b;
wire [31:0] alu_r;
// ALU operand selection per state (see ap030_exec.vh)
`define ALU_SET(op_, sz_, a_, b_, cnt_) begin alu_op = op_; alu_size = sz_; alu_a = a_; alu_b = b_; alu_cnt = cnt_; end
wire  [4:0] alu_f;
ap030_alu alu (.clk(clk), .ce(ce), .op(alu_op), .size(alu_size), .shcnt(alu_cnt), .a(alu_a), .b(alu_b),
               .flags_in(sr[4:0]), .result(alu_r), .flags_out(alu_f));

reg         md_start, md_div, md_sign;
reg  [31:0] md_a, md_hi, md_lo;
wire        md_done, md_ovf;
wire [31:0] md_rhi, md_rlo;
ap030_muldiv md (.clk(clk), .ce(ce), .rst(rst), .start(md_start), .is_div(md_div), .sign_op(md_sign),
                 .op_a(md_a), .op_hi(md_hi), .op_lo(md_lo), .done(md_done), .res_hi(md_rhi),
                 .res_lo(md_rlo), .ovf(md_ovf));

//---------------------------------------------------------------------------
// instruction pipe
//---------------------------------------------------------------------------
reg [15:0] pq [0:5];
reg  [5:0] pq_v, pq_f;
reg  [2:0] pq_n;
reg [31:0] scan_pc;        // address of pq[0] (stage C)
reg  [5:0] stop_wait;      // fetch_lazy: clocks the sequencer has been starved of instruction words
reg        due_v;          // the next longword's fetch is due ...
reg [31:0] due_scan;       // ... since the consumption reached this word
wire       stop_starve = (stop_wait == 6'd63);
assign tm_q    = {pq[0], pq[1], pq[2], pq[3], pq[4], pq[5]};
assign tm_qn   = pq_n;
assign tm_scan = scan_pc;
reg [31:0] fetch_pc;       // next longword to request
reg        fetch_skip;     // discard the first word of the next fetched longword
reg  [1:0] fetch_out;      // fetches outstanding (they return in order, two at most)
reg  [1:0] fetch_disc;     // the first of them belong to a flushed stream
reg        fetch_hold;     // no prefetching (halt, stop, refill of a bad address, RESET instruction)
reg        refill_p;       // REFILL pulse (posedge)
// per-clock pipe commands from the sequencer
reg  [1:0] pop_n;
reg        flush_req;
reg [31:0] flush_pc;
reg        pipe_load;      // RTE: preload stages C/B from the frame
reg [15:0] pipe_c, pipe_b;
reg        pipe_c_v, pipe_b_v;
reg        disp_req, sf_req, sf_need_b, sf_boundary;

wire        w0_v  = pq_v[0];
wire        w1_v  = pq_v[1];
wire        w0_f  = pq_f[0];
wire        w1_f  = pq_f[1];
wire [15:0] w0    = pq[0];
wire [15:0] w1    = pq[1];
wire        have2 = pq_v[0] & pq_v[1];

// pop_n is decided late (for example, DBcc can dispatch after reading its
// counter). Compare each possible post-consumption address in parallel,
// then select a single bit; do not put a 32-bit adder and comparator after
// pop_n on the fetch enable path. Entry 4 uses an already pending due_scan.
(* keep *) wire [4:0] fetch_model_allow;
genvar fp;
generate for (fp = 0; fp < 5; fp = fp + 1) begin : g_fetch_model
	localparam [31:0] POP_BYTES = 2 * fp;
	wire [31:0] at = (fp == 4) ? due_scan : scan_pc + POP_BYTES;
	assign fetch_model_allow[fp] =
		(!fetch_stop_v || ((fetch_stop >= 32'd2) && (at < fetch_stop - 32'd2))) &&
		(!fetch_scan_v || (fetch_scan_to >= fetch_pc) ||
		 ((fetch_scan_to >= 32'd4) && (fetch_scan_to - 32'd4 >= at)));
end endgenerate

//---------------------------------------------------------------------------
// interrupt synchronizer (UM 8.1.9: two consecutive falling-edge samples)
//---------------------------------------------------------------------------
reg [2:0] ipl_s1, ipl_s2;
always @(negedge clk) if (ce_f) begin
	ipl_s1 <= ~ipl_n;
	ipl_s2 <= ipl_s1;
end
reg [2:0] irq_lvl;         // recognized level
reg       nmi_edge;        // a transition to level 7 has not been serviced
reg       irq_taken7;      // pulse from the sequencer: level 7 accepted
always @(posedge clk) if (ce) begin
	if (rst) begin irq_lvl <= 3'd0; nmi_edge <= 1'b0; end
	else begin
		if (ipl_s1 == ipl_s2) begin
			if (ipl_s2 == 3'd7 && irq_lvl != 3'd7) nmi_edge <= 1'b1;
			irq_lvl <= ipl_s2;
		end
		if (irq_taken7) nmi_edge <= 1'b0;
	end
end
wire irq_pend = (irq_lvl > sr[10:8]) || (irq_lvl == 3'd7 && nmi_edge);
reg  ipend_r;
assign ipend_n = ~ipend_r;

//---------------------------------------------------------------------------
// sequencer registers
//---------------------------------------------------------------------------
reg  [7:0] state;
reg [15:0] ir;             // operation word
reg [15:0] ext;            // second word (bitfield, MUL/DIV, CAS, CHK2, MOVES, MOVEC, MMU, coprocessor)
reg [31:0] pc_i;           // address of the current instruction
reg [31:0] ea, ea2;        // effective addresses
(* dont_retime *) reg [31:0] src, dst;
reg [31:0] tmp, tmp2;
reg [16:0] tmp3;

reg  [7:0] cnt;
reg  [7:0] sub;
reg [15:0] mm_mask;
reg        ea_pc;          // the EA is PC-relative: its reads are program references (UM 2.4)
reg        ea_sel;         // 0: EA from ir[5:0], 1: MOVE destination from ir[11:6]
reg  [7:0] ea_ret;         // state after the EA calculation
reg  [7:0] imm_ret;
reg        imm_tgt;        // 0: src, 1: dst
reg  [3:0] dw_dst;
reg  [7:0] dw_ret;
reg  [3:0] dw_reg;
reg        tr_t1, tr_t0;   // trace bits at the start of the instruction
reg        flow;           // the instruction changed the program flow (T0 trace)
reg        trace_pend;
reg        late_fault_pend;
// the posted write fault waiting to be taken (its own record, so that a
// fault arriving while another exception is prepared leaves that alone)
reg [31:0] lf_fa, lf_dob;  // fault address, data output buffer
reg  [8:0] lf_ssw;         // SSW DF RM RW SIZE 0 FC
reg        stopped;
reg        halted_r;
// exception bookkeeping
reg  [7:0] exc_vec;
reg  [3:0] exc_fmt;
reg [31:0] exc_pc;         // PC field
reg [15:0] exc_sr;
reg [15:0] exc_ssw;
reg  [3:0] exc_rk;         // resume kind
reg  [7:0] exc_rs;         // resume state
reg  [7:0] exc_cnt;        // cnt, dw_dst and dw_ret at the fault: the frame push
reg  [3:0] exc_dw_dst;     // loop itself uses them, so the frame takes the copies
reg  [7:0] exc_dw_ret;
reg        exc_is_irq;
reg        exc_busfault;   // processing a bus/address error: another fault halts
reg        exc_throw;      // building the throwaway frame
reg        exc_late;       // the exception is a posted write fault (exc_late_fault)
// the access an instruction was suspended at (behind a posted write fault):
// its size, R/W, FC, RMC, last RMC cycle, no-cache, and the BKPT/coprocessor
// fault flags, as frame word 45; address and data use exc_partial/exc_dib
reg [10:0] exc_held;
reg [31:0] exc_sp;         // frame base
reg  [2:0] exc_ilvl;
reg [15:0] exc_stage_c, exc_stage_b;
reg [31:0] exc_baddr;
reg [31:0] exc_fa, exc_dob, exc_dib;
`ifdef VERILATOR
wire [31:0] exc_ia = exc_fa;
`endif
reg  [2:0] exc_got;
reg [31:0] exc_partial;
reg        rte_ver_err;
reg        trace_after_exc;
// coprocessor
reg  [2:0] cp_id;
reg [15:0] cp_resp;
reg        cp_cond;        // conditional category instruction
reg  [7:0] cp_len;
reg  [7:0] cp_pos;
reg        cp_dr;
reg        cp_ca;
reg        cp_pcbit;
reg        cp_trace_wait;  // trace pending: wait for null CA=0 PF=1
wire [31:0] cp_base = {14'd0, 1'b1, 1'b0, cp_id, 13'd0};  // CIR base address
reg  [3:0] cp_kind;        // instruction category for the resume
// RESET instruction counter
reg  [9:0] rst_cnt;
// STATUS
reg  [1:0] status_cnt;
reg        status_p;
// bypass of a register write being applied in the dispatch clock
reg        byp_we;
reg  [3:0] byp_reg;
reg [31:0] byp_data;
// generic-path controls latched at dispatch
reg  [5:0] g_alu;
reg  [1:0] g_size;
reg  [1:0] g_srck, g_dstk;
reg  [3:0] g_dreg;
reg        g_flags, g_wb, g_sext, g_bitop, g_move_mem;
reg  [7:0] nx;
reg        rte_fake;       // RTE with DF clear on a read: deliver the DIB as the data
reg        rerun_merge;    // a rerun read completes a partially read operand
reg        exc_active;     // exception processing in progress
reg        cpu_flt_ill;    // a bus error on this CPU-space cycle is an illegal instruction (BKPT)
reg        cpu_flt_fline;  // ... is an F-line exception (first coprocessor access)
reg        iack_pc_i;      // interrupt frame carries the instruction address (Busy primitive)
reg        iack_cpmid;     // interrupt frame is a coprocessor mid-instruction frame (null, CA, IA)

// The sequencer is in a state that takes words from the instruction queue
// (the instruction boundary, immediates, extension words, branch
// displacements, coprocessor operand words).  These states only stay put
// while a word they need is not queued; with fewer than two words queued
// and none on the way, the sequencer is starved (the fetch_lazy guard).
wire pipe_consumer = (state == S_FETCH && !stopped) || state == S_IMM || state == S_EA || state == S_EA_FULL ||
                     state == S_EA_IND || state == S_BCC || state == S_TRAPCC || state == S_LINK || state == S_CAS2_0 ||
                     state == S_CPBCC2 || state == S_CPDBCC2 || state == S_CPTRAP2 || state == S_CP_ISTREAM ||
                     state == S_CPXEA;

// interrupt processing in progress (masks IPEND)
wire exc_is_irq_active = (state == S_EXC0 || state == S_EXC1 || state == S_EXC2 || state == S_EXC3 || state == S_IACK) && exc_is_irq;
assign halted = halted_r;
assign dbg_pc = pc_i;
assign dbg_sr = sr;
assign dbg_state = state;

//---------------------------------------------------------------------------
// decoder: decodes the next instruction word w0 (pq[0])
//---------------------------------------------------------------------------
wire [15:0] dw = w0;
// ---- begin core/ap030_decode.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - instruction decoder (included by ap030_core.v)
//
// Decodes the word `dw` (the word being dispatched, or ir afterwards) into
// the first sequencer state and the generic-path controls.  Instructions
// that share the read-operate-write pattern use the generic path; the
// others get their own first state.

reg  [7:0] dc_first;
reg  [1:0] dc_size;
reg  [5:0] dc_alu;
reg  [1:0] dc_srck;     // 0 register, 1 immediate, 2 memory EA, 3 quick
reg  [1:0] dc_dstk;     // 0 register, 1 memory EA, 2 none, 3 immediate (BTST #,#)
reg  [3:0] dc_sreg, dc_dreg;
reg        dc_flags;    // update CCR
reg        dc_wb;       // write the result
reg        dc_dstrd;    // memory destination is read first
reg        dc_sext;     // sign extend the source to 32 bits (address arithmetic)
reg        dc_bitop;    // bit number modulo 8 (memory) / 32 (register)
reg        dc_priv;
reg        dc_illegal;
reg [31:0] dc_quick;
reg        dc_move_mem; // MOVE to a memory destination
reg        dc_ext;      // second word is part of the operation
reg        dc_eaonly_r; // evaluate memory EA before dc_first

localparam SK_REG = 2'd0, SK_IMM = 2'd1, SK_EA = 2'd2, SK_QUICK = 2'd3;
localparam DK_REG = 2'd0, DK_EA = 2'd1, DK_NONE = 2'd2, DK_IMM = 2'd3;

// EA classification of dw[5:0]
wire [2:0] em = dw[5:3];
wire [2:0] er = dw[2:0];
wire ea_dn   = (em == 3'b000);
wire ea_an   = (em == 3'b001);
wire ea_ind  = (em == 3'b010);
wire ea_pi   = (em == 3'b011);
wire ea_pd   = (em == 3'b100);
wire ea_d16  = (em == 3'b101);
wire ea_idx  = (em == 3'b110);
wire ea_absw = (em == 3'b111) && (er == 3'b000);
wire ea_absl = (em == 3'b111) && (er == 3'b001);
wire ea_pcd  = (em == 3'b111) && (er == 3'b010);
wire ea_pci  = (em == 3'b111) && (er == 3'b011);
wire ea_imm  = (em == 3'b111) && (er == 3'b100);
wire ea_bad  = (em == 3'b111) && (er[2:0] > 3'b100);
wire ea_mem      = ea_ind | ea_pi | ea_pd | ea_d16 | ea_idx | ea_absw | ea_absl | ea_pcd | ea_pci;
wire ea_memalt   = ea_ind | ea_pi | ea_pd | ea_d16 | ea_idx | ea_absw | ea_absl;
wire ea_ctrl     = ea_ind | ea_d16 | ea_idx | ea_absw | ea_absl | ea_pcd | ea_pci;
wire ea_ctrlalt  = ea_ind | ea_d16 | ea_idx | ea_absw | ea_absl;
wire ea_data     = ea_dn | ea_mem | ea_imm;
wire ea_dataalt  = ea_dn | ea_memalt;
wire ea_alt      = ea_dn | ea_an | ea_memalt;
wire ea_any      = !ea_bad;
wire [1:0] ea_srck = (ea_dn | ea_an) ? SK_REG : ea_imm ? SK_IMM : SK_EA;

// MOVE destination classification (dw[8:6] mode, dw[11:9] register)
wire [2:0] dm = dw[8:6];
wire [2:0] dr = dw[11:9];
wire dm_dn   = (dm == 3'b000);
wire dm_an   = (dm == 3'b001);
wire dm_mem  = (dm == 3'b010) | (dm == 3'b011) | (dm == 3'b100) | (dm == 3'b101) | (dm == 3'b110) |
               ((dm == 3'b111) && (dr == 3'b000 || dr == 3'b001));

wire [1:0] sz_std = dw[7:6];   // 00 B 01 W 10 L

always @* begin
	dc_first = S_GEN_EXEC;
	dc_size = `SZ_L;
	dc_alu = `ALU_MOVE;
	dc_srck = SK_REG; dc_dstk = DK_REG;
	dc_sreg = {ea_an, dw[2:0]};
	dc_dreg = {1'b0, dw[11:9]};
	dc_flags = 1'b1; dc_wb = 1'b1; dc_dstrd = 1'b1; dc_sext = 1'b0; dc_bitop = 1'b0;
	dc_priv = 1'b0; dc_illegal = 1'b0; dc_quick = 32'd0; dc_move_mem = 1'b0;
	dc_ext = 1'b0; dc_eaonly_r = 1'b0;

	case (dw[15:12])
	//------------------------------------------------------------------ 0000
	4'h0: begin
		if (dw[8]) begin
			if (ea_an) begin
				// MOVEP
				dc_first = S_MOVEP0; dc_ext = 1'b1;
				dc_size = dw[6] ? `SZ_L : `SZ_W;
			end else begin
				// dynamic bit operations: BTST/BCHG/BCLR/BSET Dn,<ea>
				dc_bitop = 1'b1;
				dc_sreg = {1'b0, dw[11:9]};
				case (dw[7:6])
					2'b00: begin dc_alu = `ALU_BTST; dc_wb = 1'b0; end
					2'b01: dc_alu = `ALU_BCHG;
					2'b10: dc_alu = `ALU_BCLR;
					default: dc_alu = `ALU_BSET;
				endcase
				if (ea_dn) begin dc_size = `SZ_L; dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
				else begin
					dc_size = `SZ_B;
					if (ea_imm && dw[7:6] == 2'b00) dc_dstk = DK_IMM;
					else begin dc_dstk = DK_EA; if (!(dw[7:6] == 2'b00 ? ea_mem : ea_memalt)) dc_illegal = 1'b1; end
				end
			end
		end else if (dw[11:9] == 3'b100) begin
			// static bit operations: BTST/BCHG/BCLR/BSET #n,<ea> (the bit
			// number is one word; the operand is a byte in memory, long in Dn)
			dc_bitop = 1'b1;
			dc_srck = SK_IMM;
			dc_size = `SZ_B;
			case (dw[7:6])
				2'b00: begin dc_alu = `ALU_BTST; dc_wb = 1'b0; end
				2'b01: dc_alu = `ALU_BCHG;
				2'b10: dc_alu = `ALU_BCLR;
				default: dc_alu = `ALU_BSET;
			endcase
			if (ea_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; dc_size = `SZ_L; end
			else begin dc_dstk = DK_EA; if (!(dw[7:6] == 2'b00 ? ea_mem : ea_memalt)) dc_illegal = 1'b1; end
		end else if (dw[7:6] == 2'b11) begin
			// CHK2/CMP2 (00C0/02C0/04C0), CAS (0AC0/0CC0/0EC0), CAS2 (0CFC/0EFC), CALLM/RTM (illegal)
			case (dw[11:9])
				3'b000, 3'b001, 3'b010: begin
					dc_first = S_CHK2_1; dc_srck = SK_EA; dc_ext = 1'b1;
					dc_size = dw[10:9];
					if (!ea_ctrl) dc_illegal = 1'b1;
				end
				3'b101, 3'b110, 3'b111: begin
					dc_size = dw[10:9] - 2'd1; dc_ext = 1'b1;
					if (ea_imm && dw[11:9] != 3'b101) dc_first = S_CAS2_0;
					else begin dc_first = S_CAS0; dc_eaonly_r = 1'b1; if (!ea_memalt) dc_illegal = 1'b1; end
				end
				default: dc_illegal = 1'b1;
			endcase
		end else if (dw[11:9] == 3'b111) begin
			// MOVES
			dc_first = S_MOVES0; dc_ext = 1'b1; dc_eaonly_r = 1'b1;
			dc_size = sz_std;
			dc_priv = 1'b1;
			if (!ea_memalt) dc_illegal = 1'b1;
		end else begin
			// ORI ANDI SUBI ADDI EORI CMPI #imm,<ea>; to CCR/SR
			dc_srck = SK_IMM;
			dc_size = sz_std;
			case (dw[11:9])
				3'b000: dc_alu = `ALU_OR;
				3'b001: dc_alu = `ALU_AND;
				3'b010: dc_alu = `ALU_SUB;
				3'b011: dc_alu = `ALU_ADD;
				3'b101: dc_alu = `ALU_EOR;
				default: begin dc_alu = `ALU_CMP; dc_wb = 1'b0; end
			endcase
			if (ea_imm && (dw[11:9] == 3'b000 || dw[11:9] == 3'b001 || dw[11:9] == 3'b101) && (dw[7:6] != 2'b10)) begin
				// to CCR (byte) / SR (word)
				dc_dstk = DK_NONE;
				dc_priv = dw[6];
				dc_first = S_MOVE_SR;
			end else if (ea_dn) begin
				dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]};
			end else begin
				dc_dstk = DK_EA;
				if (!(dw[11:9] == 3'b110 ? ea_mem : ea_memalt)) dc_illegal = 1'b1;
			end
		end
	end

	//------------------------------------------------------------------ MOVE
	4'h1, 4'h2, 4'h3: begin
		dc_size = (dw[13:12] == 2'b01) ? `SZ_B : (dw[13:12] == 2'b11) ? `SZ_W : `SZ_L;
		dc_alu = `ALU_MOVE;
		dc_dstrd = 1'b0;
		dc_srck = ea_srck;
		if (!ea_any || (ea_an && dc_size == `SZ_B)) dc_illegal = 1'b1;
		if (dm_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[11:9]}; end
		else if (dm_an) begin
			// MOVEA
			dc_dstk = DK_REG; dc_dreg = {1'b1, dw[11:9]}; dc_alu = `ALU_MOVEA; dc_flags = 1'b0; dc_sext = 1'b1;
			if (dc_size == `SZ_B) dc_illegal = 1'b1;
		end else if (dm_mem) begin
			dc_dstk = DK_EA; dc_move_mem = 1'b1;
			if (dc_srck == SK_REG) dc_first = S_MOVE_DEA;
		end else dc_illegal = 1'b1;
	end

	//------------------------------------------------------------------ 0100
	4'h4: begin
		if (dw[8]) begin
			case (dw[7:6])
				2'b11: begin
					if (dw[11:9] == 3'b100 && ea_dn) begin   // EXTB.L Dn ($49C0)
						dc_alu = `ALU_EXTB; dc_size = `SZ_L; dc_srck = SK_QUICK; dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]};
					end else begin dc_first = S_LEA; dc_eaonly_r = 1'b1; dc_flags = 1'b0; if (!ea_ctrl) dc_illegal = 1'b1; end   // LEA
				end
				2'b10, 2'b00: begin
					dc_first = S_CHK; dc_size = dw[7] ? `SZ_W : `SZ_L; dc_flags = 1'b0; dc_wb = 1'b0;
					dc_srck = ea_srck;
					if (!ea_data) dc_illegal = 1'b1;
				end
				default: dc_illegal = 1'b1;
			endcase
		end else case (dw[11:9])
			3'b000: begin  // NEGX / MOVE from SR
				if (dw[7:6] == 2'b11) begin dc_first = S_MOVE_FSR; dc_eaonly_r = 1'b1; dc_size = `SZ_W; dc_dreg = {1'b0, dw[2:0]}; dc_priv = 1'b1; if (!ea_dataalt) dc_illegal = 1'b1; end
				else begin dc_alu = `ALU_NEGX; dc_size = sz_std; dc_srck = SK_QUICK;
					if (ea_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
					else begin dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
				end
			end
			3'b001: begin  // CLR / MOVE from CCR
				if (dw[7:6] == 2'b11) begin dc_first = S_MOVE_FSR; dc_eaonly_r = 1'b1; dc_size = `SZ_W; dc_dreg = {1'b0, dw[2:0]}; if (!ea_dataalt) dc_illegal = 1'b1; end
				else begin dc_alu = `ALU_CLR; dc_size = sz_std; dc_srck = SK_QUICK; dc_dstrd = 1'b0;
					if (ea_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
					else begin dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
				end
			end
			3'b010: begin  // NEG / MOVE to CCR
				if (dw[7:6] == 2'b11) begin
					dc_first = S_MOVE_SR; dc_size = `SZ_W; dc_dstk = DK_NONE;
					dc_srck = ea_srck; if (!ea_data) dc_illegal = 1'b1;
				end else begin dc_alu = `ALU_NEG; dc_size = sz_std; dc_srck = SK_QUICK;
					if (ea_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
					else begin dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
				end
			end
			3'b011: begin  // NOT / MOVE to SR
				if (dw[7:6] == 2'b11) begin
					dc_first = S_MOVE_SR; dc_size = `SZ_W; dc_priv = 1'b1; dc_dstk = DK_NONE;
					dc_srck = ea_srck; if (!ea_data) dc_illegal = 1'b1;
				end else begin dc_alu = `ALU_NOT; dc_size = sz_std; dc_srck = SK_QUICK;
					if (ea_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
					else begin dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
				end
			end
			3'b100: begin
				case (dw[7:6])
					2'b00: begin  // NBCD / LINK.L
						if (ea_an) begin dc_first = S_LINK; dc_ext = 1'b1; dc_size = `SZ_L; end
						else begin dc_alu = `ALU_NBCD; dc_size = `SZ_B; dc_srck = SK_QUICK;
							if (ea_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
							else begin dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
						end
					end
					2'b01: begin  // SWAP / BKPT / PEA
						if (ea_dn) begin dc_alu = `ALU_SWAP; dc_size = `SZ_L; dc_srck = SK_QUICK; dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
						else if (ea_an) dc_first = S_BKPT;
						else begin dc_first = S_PEA; dc_eaonly_r = 1'b1; if (!ea_ctrl) dc_illegal = 1'b1; end
					end
					default: begin  // EXT.W / EXT.L / MOVEM reg->mem
						if (ea_dn) begin dc_alu = `ALU_EXT; dc_size = dw[6] ? `SZ_L : `SZ_W; dc_srck = SK_QUICK; dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
						else begin dc_first = S_MOVEM0; dc_ext = 1'b1; dc_eaonly_r = !ea_pi && !ea_pd; dc_size = dw[6] ? `SZ_L : `SZ_W; if (!(ea_ctrlalt || ea_pd)) dc_illegal = 1'b1; end
					end
				endcase
			end
			3'b101: begin  // TST / TAS / ILLEGAL
				if (dw[7:6] == 2'b11) begin
					if (ea_imm) dc_illegal = 1'b1;   // ILLEGAL ($4AFC)
					else begin dc_alu = `ALU_TAS; dc_size = `SZ_B;
						if (ea_dn) begin dc_srck = SK_QUICK; dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
						else begin dc_first = S_TAS; dc_eaonly_r = 1'b1; if (!ea_memalt) dc_illegal = 1'b1; end
					end
				end else begin
					dc_alu = `ALU_TST; dc_size = sz_std; dc_wb = 1'b0; dc_dstk = DK_NONE;
					dc_srck = ea_srck;
					if (!ea_any || (ea_an && dc_size == `SZ_B)) dc_illegal = 1'b1;
				end
			end
			3'b110: begin  // MULL / DIVL / MOVEM mem->reg
				if (dw[7]) begin dc_first = S_MOVEM0; dc_ext = 1'b1; dc_eaonly_r = !ea_pi && !ea_pd; dc_size = dw[6] ? `SZ_L : `SZ_W; if (!(ea_ctrl || ea_pi)) dc_illegal = 1'b1; end
				else begin
					dc_first = S_MULDIV0; dc_ext = 1'b1; dc_size = `SZ_L; dc_dstk = DK_NONE;
					dc_srck = ea_srck; if (!ea_data) dc_illegal = 1'b1;
				end
			end
			default: begin  // 3'b111
				case (dw[7:6])
					2'b01: begin
						case (dw[5:3])
							3'b000, 3'b001: dc_first = S_TRAP;
							3'b010: begin dc_first = S_LINK; dc_ext = 1'b1; dc_size = `SZ_W; end
							3'b011: dc_first = S_UNLK;
							3'b100, 3'b101: begin dc_first = S_MOVE_USP; dc_priv = 1'b1; end
							3'b110: begin
								case (dw[2:0])
									3'b000: begin dc_first = S_RESETI; dc_priv = 1'b1; end
									3'b001: dc_first = S_NOP;
									3'b010: begin dc_first = S_STOP; dc_ext = 1'b1; dc_priv = 1'b1; end
									3'b011: begin dc_first = S_RTE0; dc_priv = 1'b1; end
									3'b100: begin dc_first = S_RTD; dc_ext = 1'b1; end
									3'b101: dc_first = S_RTS;
									3'b110: dc_first = S_TRAPCC;   // TRAPV
									default: dc_first = S_RTR;
								endcase
							end
							default: begin
								if (dw[2:1] == 2'b01) begin dc_first = S_MOVEC; dc_ext = 1'b1; dc_priv = 1'b1; end   // 4E7A/4E7B
								else dc_illegal = 1'b1;
							end
						endcase
					end
					2'b10: begin dc_first = S_JSR; dc_eaonly_r = 1'b1; if (!ea_ctrl) dc_illegal = 1'b1; end
					2'b11: begin dc_first = S_JMP; dc_eaonly_r = 1'b1; if (!ea_ctrl) dc_illegal = 1'b1; end
					default: dc_illegal = 1'b1;
				endcase
			end
		endcase
	end

	//------------------------------------------------------------------ 0101 ADDQ/SUBQ/Scc/DBcc/TRAPcc
	4'h5: begin
		if (dw[7:6] == 2'b11) begin
			if (ea_an) begin dc_first = S_DBCC; dc_ext = 1'b1; end
			else if (em == 3'b111 && (er == 3'b010 || er == 3'b011 || er == 3'b100)) dc_first = S_TRAPCC;
			else begin dc_first = S_SCC; dc_eaonly_r = 1'b1; dc_size = `SZ_B; dc_dreg = {1'b0, dw[2:0]}; if (!ea_dataalt) dc_illegal = 1'b1; end
		end else begin
			dc_size = sz_std;
			dc_srck = SK_QUICK;
			dc_quick = (dw[11:9] == 3'd0) ? 32'd8 : {29'd0, dw[11:9]};
			dc_alu = dw[8] ? `ALU_SUB : `ALU_ADD;
			if (ea_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
			else if (ea_an) begin
				dc_dstk = DK_REG; dc_dreg = {1'b1, dw[2:0]}; dc_flags = 1'b0; dc_size = `SZ_L;
				dc_alu = dw[8] ? `ALU_SUBA : `ALU_ADDA;
				if (sz_std == `SZ_B) dc_illegal = 1'b1;
			end else begin dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
		end
	end

	//------------------------------------------------------------------ 0110 Bcc/BRA/BSR
	4'h6: dc_first = S_BCC;

	//------------------------------------------------------------------ 0111 MOVEQ
	4'h7: begin
		if (dw[8]) dc_illegal = 1'b1;
		else begin
			dc_alu = `ALU_MOVE; dc_size = `SZ_L; dc_srck = SK_QUICK; dc_quick = sext8(dw[7:0]);
			dc_dstk = DK_REG; dc_dreg = {1'b0, dw[11:9]};
		end
	end

	//------------------------------------------------------------------ 1000 OR/DIV/SBCD/PACK/UNPK
	4'h8: begin
		case (dw[8:6])
			3'b011, 3'b111: begin
				dc_first = S_MULDIV0; dc_size = `SZ_W; dc_dstk = DK_REG; dc_dreg = {1'b0, dw[11:9]};
				dc_srck = ea_srck; if (!ea_data) dc_illegal = 1'b1;
			end
			3'b100: begin
				if (ea_dn) begin dc_alu = `ALU_SBCD; dc_size = `SZ_B; dc_srck = SK_REG; dc_dstk = DK_REG; end
				else if (ea_an) begin dc_first = S_PACK; dc_alu = `ALU_SBCD; dc_size = `SZ_B; end
				else begin dc_alu = `ALU_OR; dc_size = sz_std; dc_srck = SK_REG; dc_sreg = {1'b0, dw[11:9]}; dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
			end
			3'b101, 3'b110: begin
				if (ea_dn || ea_an) begin dc_first = S_PACK; dc_ext = 1'b1; end   // PACK / UNPK
				else begin dc_alu = `ALU_OR; dc_size = sz_std; dc_srck = SK_REG; dc_sreg = {1'b0, dw[11:9]}; dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
			end
			default: begin  // OR <ea>,Dn
				dc_alu = `ALU_OR; dc_size = sz_std; dc_dstk = DK_REG;
				dc_srck = ea_srck; if (!ea_data) dc_illegal = 1'b1;
			end
		endcase
	end

	//------------------------------------------------------------------ 1001 SUB, 1101 ADD
	4'h9, 4'hD: begin
		case (dw[8:6])
			3'b011, 3'b111: begin  // SUBA/ADDA
				dc_alu = dw[14] ? `ALU_ADDA : `ALU_SUBA; dc_flags = 1'b0; dc_sext = 1'b1;
				dc_size = dw[8] ? `SZ_L : `SZ_W;
				dc_dstk = DK_REG; dc_dreg = {1'b1, dw[11:9]};
				dc_srck = ea_srck; if (!ea_any) dc_illegal = 1'b1;
			end
			3'b100, 3'b101, 3'b110: begin
				dc_size = dw[7:6];
				if (ea_dn) begin dc_alu = dw[14] ? `ALU_ADDX : `ALU_SUBX; dc_srck = SK_REG; dc_dstk = DK_REG; end
				else if (ea_an) begin dc_alu = dw[14] ? `ALU_ADDX : `ALU_SUBX; dc_first = S_PACK; end   // -(Ay),-(Ax) form
				else begin dc_alu = dw[14] ? `ALU_ADD : `ALU_SUB; dc_srck = SK_REG; dc_sreg = {1'b0, dw[11:9]}; dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
			end
			default: begin  // SUB/ADD <ea>,Dn
				dc_alu = dw[14] ? `ALU_ADD : `ALU_SUB; dc_size = sz_std; dc_dstk = DK_REG;
				dc_srck = ea_srck;
				if (!ea_any || (ea_an && dc_size == `SZ_B)) dc_illegal = 1'b1;
			end
		endcase
	end

	//------------------------------------------------------------------ 1010 A-line
	4'hA: dc_illegal = 1'b1;

	//------------------------------------------------------------------ 1011 CMP/CMPA/EOR/CMPM
	4'hB: begin
		case (dw[8:6])
			3'b011, 3'b111: begin  // CMPA
				dc_alu = `ALU_CMPA; dc_wb = 1'b0; dc_sext = 1'b1;
				dc_size = dw[8] ? `SZ_L : `SZ_W;
				dc_dstk = DK_REG; dc_dreg = {1'b1, dw[11:9]};
				dc_srck = ea_srck; if (!ea_any) dc_illegal = 1'b1;
			end
			3'b100, 3'b101, 3'b110: begin
				dc_size = dw[7:6];
				if (ea_an) begin dc_first = S_PACK; dc_alu = `ALU_CMP; end   // CMPM (Ay)+,(Ax)+
				else begin
					dc_alu = `ALU_EOR; dc_srck = SK_REG; dc_sreg = {1'b0, dw[11:9]};
					if (ea_dn) begin dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]}; end
					else begin dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
				end
			end
			default: begin  // CMP <ea>,Dn
				dc_alu = `ALU_CMP; dc_size = sz_std; dc_wb = 1'b0; dc_dstk = DK_REG;
				dc_srck = ea_srck;
				if (!ea_any || (ea_an && dc_size == `SZ_B)) dc_illegal = 1'b1;
			end
		endcase
	end

	//------------------------------------------------------------------ 1100 AND/MUL/ABCD/EXG
	4'hC: begin
		case (dw[8:6])
			3'b011, 3'b111: begin
				dc_first = S_MULDIV0; dc_size = `SZ_W; dc_dstk = DK_REG; dc_dreg = {1'b0, dw[11:9]};
				dc_srck = ea_srck; if (!ea_data) dc_illegal = 1'b1;
			end
			3'b100: begin
				if (ea_dn) begin dc_alu = `ALU_ABCD; dc_size = `SZ_B; dc_srck = SK_REG; dc_dstk = DK_REG; end
				else if (ea_an) begin dc_first = S_PACK; dc_alu = `ALU_ABCD; dc_size = `SZ_B; end
				else begin dc_alu = `ALU_AND; dc_size = sz_std; dc_srck = SK_REG; dc_sreg = {1'b0, dw[11:9]}; dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
			end
			3'b101, 3'b110: begin
				if (ea_dn && dw[8:6] == 3'b101) dc_first = S_EXG;        // EXG Dx,Dy
				else if (ea_an && dw[8:6] == 3'b101) dc_first = S_EXG;   // EXG Ax,Ay
				else if (ea_an && dw[8:6] == 3'b110) dc_first = S_EXG;   // EXG Dx,Ay
				else if (ea_dn) dc_illegal = 1'b1;
				else begin dc_alu = `ALU_AND; dc_size = sz_std; dc_srck = SK_REG; dc_sreg = {1'b0, dw[11:9]}; dc_dstk = DK_EA; if (!ea_memalt) dc_illegal = 1'b1; end
			end
			default: begin
				dc_alu = `ALU_AND; dc_size = sz_std; dc_dstk = DK_REG;
				dc_srck = ea_srck; if (!ea_data) dc_illegal = 1'b1;
			end
		endcase
	end

	//------------------------------------------------------------------ 1110 shifts / bitfields
	4'hE: begin
		if (dw[11] && dw[7:6] == 2'b11) begin
			dc_first = S_BF0; dc_ext = 1'b1; dc_eaonly_r = 1'b1;
			if (!(ea_dn || ea_ctrlalt || (dw[10:8] == 3'b000 || dw[10:8] == 3'b001 || dw[10:8] == 3'b011 || dw[10:8] == 3'b101) && ea_ctrl)) dc_illegal = 1'b1;
		end else if (dw[7:6] == 2'b11) begin
			// memory shift: word, count 1
			dc_size = `SZ_W; dc_srck = SK_QUICK; dc_quick = 32'd1; dc_dstk = DK_EA;
			case (dw[10:9])
				2'b00: dc_alu = dw[8] ? `ALU_ASL : `ALU_ASR;
				2'b01: dc_alu = dw[8] ? `ALU_LSL : `ALU_LSR;
				2'b10: dc_alu = dw[8] ? `ALU_ROXL : `ALU_ROXR;
				default: dc_alu = dw[8] ? `ALU_ROL : `ALU_ROR;
			endcase
			if (!ea_memalt) dc_illegal = 1'b1;
		end else begin
			// register shift: count immediate (0 -> 8) or Dn mod 64
			dc_size = sz_std;
			dc_dstk = DK_REG; dc_dreg = {1'b0, dw[2:0]};
			if (dw[5]) begin dc_srck = SK_REG; dc_sreg = {1'b0, dw[11:9]}; end
			else begin dc_srck = SK_QUICK; dc_quick = (dw[11:9] == 3'd0) ? 32'd8 : {29'd0, dw[11:9]}; end
			case (dw[4:3])
				2'b00: dc_alu = dw[8] ? `ALU_ASL : `ALU_ASR;
				2'b01: dc_alu = dw[8] ? `ALU_LSL : `ALU_LSR;
				2'b10: dc_alu = dw[8] ? `ALU_ROXL : `ALU_ROXR;
				default: dc_alu = dw[8] ? `ALU_ROL : `ALU_ROR;
			endcase
		end
	end

	//------------------------------------------------------------------ 1111 MMU / coprocessor
	default: begin
		if (dw[11:9] == 3'b000) begin
			// MMU instructions (CpID 0): privileged, the second word decides
			dc_first = S_PMMU0; dc_ext = 1'b1;
			dc_priv = 1'b1;
		end else begin
			case (dw[8:6])
				3'b000: begin dc_first = S_CP0; dc_ext = 1'b1; end       // cpGEN
				3'b001: begin
					dc_ext = 1'b1;
					if (ea_an) dc_first = S_CPDBCC;          // cpDBcc
					else if (em == 3'b111 && er[2:1] != 2'b00) begin
						// cpTRAPcc: opmode 010/011/100 in er; 101-111 are neither a cpTRAPcc
						// opmode nor a cpScc EA: F-line (UM Table 10-1, 10.5.2.2)
						dc_first = S_CPTRAP;
						if (er[2] && er[1:0] != 2'b00) dc_illegal = 1'b1;
					end
					else begin dc_first = S_CPSCC; dc_dreg = {1'b0, dw[2:0]}; dc_size = `SZ_B; end   // cpScc: byte operand
				end
				3'b010, 3'b011: dc_first = S_CPBCC;        // cpBcc.W / .L
				3'b100: begin dc_first = S_CPSAVE0; dc_eaonly_r = !ea_pd; dc_priv = 1'b1; if (!(ea_ctrlalt || ea_pd)) dc_illegal = 1'b1; end
				3'b101: begin dc_first = S_CPREST0; dc_eaonly_r = !ea_pi; dc_priv = 1'b1; if (!(ea_ctrl || ea_pi)) dc_illegal = 1'b1; end
				default: dc_illegal = 1'b1;                // F-line emulator
			endcase
		end
	end
	endcase
end

// an instruction that takes an exception at its dispatch (illegal, A-line,
// F-line, privilege violation) is identified from its operation word alone
// (UM 8.1.5, 8.1.6): it neither waits for its second word nor takes the
// bus error of a faulted prefetch of it, which only an instruction that
// uses the word takes (UM 8.1.2)
wire dc_trap = dc_illegal || (dc_priv && !sr_s);
// instructions whose second word is part of the operation (popped with the opcode)
wire dc_needs_ext = !dc_trap && dc_ext;
// instructions that evaluate their memory EA (no operand read) before their first state
wire dc_eaonly = ea_mem && dc_eaonly_r;
// ---- end core/ap030_decode.vh ----

// EA classification of ir[5:0] for post-dispatch states (coprocessor / PMMU)
wire [2:0] ir_em      = ir[5:3];
wire [2:0] ir_er      = ir[2:0];
wire       ir_ea_dn   = (ir_em == 3'b000);
wire       ir_ea_an   = (ir_em == 3'b001);
wire       ir_ea_ind  = (ir_em == 3'b010);
wire       ir_ea_pi   = (ir_em == 3'b011);
wire       ir_ea_pd   = (ir_em == 3'b100);
wire       ir_ea_d16  = (ir_em == 3'b101);
wire       ir_ea_idx  = (ir_em == 3'b110);
wire       ir_ea_absw = (ir_em == 3'b111) && (ir_er == 3'b000);
wire       ir_ea_absl = (ir_em == 3'b111) && (ir_er == 3'b001);
wire       ir_ea_pcd  = (ir_em == 3'b111) && (ir_er == 3'b010);
wire       ir_ea_pci  = (ir_em == 3'b111) && (ir_er == 3'b011);
wire       ir_ea_imm  = (ir_em == 3'b111) && (ir_er == 3'b100);
wire       ir_ea_bad  = (ir_em == 3'b111) && (ir_er[2:0] > 3'b100);
wire       ir_ea_mem     = ir_ea_ind | ir_ea_pi | ir_ea_pd | ir_ea_d16 | ir_ea_idx | ir_ea_absw | ir_ea_absl | ir_ea_pcd | ir_ea_pci;
wire       ir_ea_memalt  = ir_ea_ind | ir_ea_pi | ir_ea_pd | ir_ea_d16 | ir_ea_idx | ir_ea_absw | ir_ea_absl;
wire       ir_ea_ctrl    = ir_ea_ind | ir_ea_d16 | ir_ea_idx | ir_ea_absw | ir_ea_absl | ir_ea_pcd | ir_ea_pci;
wire       ir_ea_ctrlalt = ir_ea_ind | ir_ea_d16 | ir_ea_idx | ir_ea_absw | ir_ea_absl;
wire       ir_ea_data    = ir_ea_dn | ir_ea_mem | ir_ea_imm;
wire       ir_ea_dataalt = ir_ea_dn | ir_ea_memalt;
wire       ir_ea_alt     = ir_ea_dn | ir_ea_an | ir_ea_memalt;
wire       ir_ea_any     = !ir_ea_bad;

//---------------------------------------------------------------------------
// helpers
//---------------------------------------------------------------------------
function [31:0] sext8;  input [7:0] v;  begin sext8 = {{24{v[7]}}, v}; end endfunction
function [31:0] sext16; input [15:0] v; begin sext16 = {{16{v[15]}}, v}; end endfunction

// condition codes (PRM 3.3)
function cc_true;
	input [3:0] c;
	input [4:0] f;   // {X,N,Z,V,C}
	reg n, z, v, cf;
	begin
		n = f[3]; z = f[2]; v = f[1]; cf = f[0];
		case (c)
			4'h0: cc_true = 1'b1;
			4'h1: cc_true = 1'b0;
			4'h2: cc_true = !cf & !z;
			4'h3: cc_true = cf | z;
			4'h4: cc_true = !cf;
			4'h5: cc_true = cf;
			4'h6: cc_true = !z;
			4'h7: cc_true = z;
			4'h8: cc_true = !v;
			4'h9: cc_true = v;
			4'hA: cc_true = !n;
			4'hB: cc_true = n;
			4'hC: cc_true = (n == v);
			4'hD: cc_true = (n != v);
			4'hE: cc_true = (n == v) & !z;
			default: cc_true = (n != v) | z;
		endcase
	end
endfunction

// merge a sized result into a register value
function [31:0] merge;
	input [31:0] old; input [31:0] r; input [1:0] sz;
	begin
		case (sz)
			`SZ_B: merge = {old[31:8], r[7:0]};
			`SZ_W: merge = {old[31:16], r[15:0]};
			default: merge = r;
		endcase
	end
endfunction

function [31:0] sext_sz;
	input [31:0] v; input [1:0] sz;
	begin
		case (sz)
			`SZ_B: sext_sz = sext8(v[7:0]);
			`SZ_W: sext_sz = sext16(v[15:0]);
			default: sext_sz = v;
		endcase
	end
endfunction

// CHK2/CMP2 N and V: undefined in the PRM; the MC68020/030 values as
// tabulated by WinUAE setchk2undefinedflags (bounds and value are signed,
// sign-extended to 32 bits; the differences wrap)
function [1:0] chk2_nv;           // {N, V}
	input [31:0] lower, upper, val;
	reg n, v;
	reg ln, un, vn, vl31;
	reg [31:0] lv, uv, lu;
	reg v_lt_l, v_gt_l, v_lt_u, v_gt_u, l_gt_u;
	begin
		n = 1'b0; v = 1'b0;
		ln = lower[31]; un = upper[31]; vn = val[31];
		lv = lower - val; uv = upper - val; lu = lower - upper;
		vl31 = (lv == 32'h80000000) ? 1'b1 : !lv[31];
		v_lt_l = (lv != 32'd0) && ((vn != ln) ? vn : !lv[31]);
		v_gt_l = !v_lt_l;
		v_lt_u = (uv != 32'd0) && ((vn != un) ? vn : !uv[31]);
		v_gt_u = !v_lt_u;
		l_gt_u = (lu != 32'd0) && ((ln != un) ? !ln : !lu[31]);
		if (lv == 32'd0 || uv == 32'd0) ;
		else if (ln && !un) begin

			if (v_lt_l) n = 1'b1;
			if (!vn && v_lt_u) n = 1'b1;
			if (!vn && !lv[31]) begin
				v = 1'b1; n = v_gt_u;
			end
		end else if (!ln && un) begin
			if (!vn) n = 1'b1;
			if (v_gt_u) n = 1'b1;
			if (v_gt_l && !uv[31]) begin v = 1'b1; n = 1'b0; end
		end else if (!ln && !un && l_gt_u) begin
			if (v_gt_u && v_lt_l) n = 1'b1;
			if (vn && lv[31]) v = 1'b1;
			if (vn && !lv[31]) n = 1'b1;
		end else if (!ln && !un) begin
			if (!vn && v_lt_l) n = 1'b1;
			if (v_gt_u) n = 1'b1;
			if (vn && uv[31]) begin v = 1'b1; n = 1'b1; end
		end else if (l_gt_u) begin
			if (!vn) n = 1'b1;
			if (v_gt_u && v_lt_l) n = 1'b1;
			if (!vn && vl31) begin n = 1'b0; v = 1'b1; end
		end else begin
			if (v_lt_l) n = 1'b1;
			if (vn && v_gt_u) n = 1'b1;
			if (!vn && vl31) begin n = 1'b1; v = 1'b1; end
		end
		chk2_nv = {n, v};
	end
endfunction

function [31:0] size_bytes;
	input [1:0] sz; input a7;
	begin
		case (sz)
			`SZ_B: size_bytes = a7 ? 32'd2 : 32'd1;
			`SZ_W: size_bytes = 32'd2;
			default: size_bytes = 32'd4;
		endcase
	end
endfunction

// index register value with scale for brief/full extension words
function [31:0] index_val;
	input [31:0] xn; input [15:0] xw;
	reg [31:0] v;
	begin
		v = xw[11] ? xn : sext16(xn[15:0]);
		index_val = v << xw[10:9];
	end
endfunction

// the EA engine runs after dispatch: its fields come from ir, so that the
// dispatch multiplexer (dw) is not in the register read and address paths
wire [2:0] ea_mode = ea_sel ? ir[8:6]  : ir[5:3];
wire [2:0] ea_regn = ea_sel ? ir[11:9] : ir[2:0];
wire       ea_pcrel = !ea_sel && (ir[5:3] == 3'b111) && (ir[2:1] == 2'b01);

//---------------------------------------------------------------------------
// register read port selection
//---------------------------------------------------------------------------
always @* begin
	ra_a = {1'b1, ea_regn};       // EA base register by default
	ra_b = g_dreg;                // destination register of the current instruction
	ra_c = 4'd15;                 // A7
	case (state)
		S_EA, S_EA_FULL: ra_c = {w0[15], w0[14:12]};          // index register
		S_MOVEM1, S_CPREGS, S_CPREGS2, S_CP9: ra_a = cnt[3:0];
		S_MOVEC, S_MOVES0, S_MOVES1, S_CHK2_2: ra_a = {ext[15], ext[14:12]};
		S_CAS0, S_CAS1, S_CAS1B: begin ra_a = {1'b0, ext[2:0]}; ra_b = {1'b0, ext[8:6]}; end
		S_CAS2_0, S_CAS2_1, S_CAS2_2, S_CAS2_3, S_CAS2_4, S_CAS2_4B, S_CAS2_5, S_CAS2_5B, S_CAS2_6, S_CAS2_7, S_CAS2_8: begin
			ra_a = tmp3[16] ? {1'b0, tmp3[2:0]} : {1'b0, ext[2:0]};
			ra_b = tmp3[16] ? {1'b0, tmp3[8:6]} : {1'b0, ext[8:6]};
			ra_c = tmp3[16] ? {tmp3[15], tmp3[14:12]} : {ext[15], ext[14:12]};
		end
		S_BF0: begin ra_a = {1'b0, ext[14:12]}; ra_b = {1'b0, ext[8:6]}; ra_c = {1'b0, ext[2:0]}; end
		S_BF1, S_BF2, S_BF3, S_BFWR: begin ra_a = {1'b0, ext[14:12]}; ra_b = {1'b0, ir[2:0]}; end
		S_MULDIV0, S_MULDIV1, S_MULDIV2: begin ra_a = {1'b0, ext[14:12]}; ra_b = {1'b0, ext[2:0]}; end
		S_EXG, S_EXG2: begin
			ra_a = {ir[7:3] == 5'b01001, ir[11:9]};
			ra_b = {ir[7:3] != 5'b01000, ir[2:0]};
		end
		S_PACK, S_PACK2, S_PACK3: begin ra_a = {ir[3], ir[2:0]}; ra_b = {ir[3], ir[11:9]}; end
		S_LINK, S_LINK2, S_UNLK, S_UNLK2, S_MOVE_USP: ra_a = {1'b1, ir[2:0]};
		S_MOVEP0, S_MOVEP1, S_MOVEP2: begin ra_a = {1'b1, ir[2:0]}; ra_b = {1'b0, ir[11:9]}; end
		S_DBCC, S_CPDBCC, S_CPDBCC2, S_CPSCC2: ra_a = {1'b0, ir[2:0]};
		S_CP2, S_CP10, S_CPREG, S_CPCTRL, S_CPCTRL2, S_CPTOS, S_CPEAX,
		S_CPXFER, S_CPXFER2, S_CPXFER3, S_CPMULT, S_CPMULT2, S_CPMULT3,
		S_CPSAVE0, S_CPSAVE1, S_CPREST0, S_CPREST1: begin
			ra_a = {cp_resp[3], cp_resp[2:0]};   // single register transfer
			ra_b = {1'b1, ir[2:0]};              // An of the effective address
		end
		S_CPXEA: begin
			ra_a = {cp_resp[3], cp_resp[2:0]};
			ra_b = {1'b1, ir[2:0]};              // An direct or the address register of the EA
			ra_c = {1'b0, ir[2:0]};              // Dn direct
		end
		S_PMMU0, S_PLOAD, S_PFLUSH2, S_PTEST, S_PTEST2, S_PFLUSH, S_PMOVE_RD, S_PMOVE_RD2, S_PMOVE_RD3, S_PMOVE_WR, S_PMOVE_WR2, S_PMOVE_FIN: begin
			ra_a = {1'b0, ext[2:0]};          // Dn holding the function code
			ra_b = {1'b1, ext[7:5]};          // An for the PTEST result
		end
		default: ;
	endcase
end

//---------------------------------------------------------------------------
// STATUS / REFILL (asserted from falling edges, UM 12.7.1)
//---------------------------------------------------------------------------
(* dont_retime *) reg status_n_r, refill_n_r;
always @(negedge clk) if (ce_f) begin
	status_n_r <= status_p;
	refill_n_r <= refill_p;
end
assign status_n = status_n_r;
assign refill_n = refill_n_r;

//---------------------------------------------------------------------------
// exception frame word generator (UM 8.4)
//---------------------------------------------------------------------------
// ---- begin core/ap030_frame.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - exception stack frame words (UM 8.4, included by ap030_core.v)
//
// frame_word(i) is word i (offset 2*i) of the frame being built.  Formats:
//   $0/$1  4 words   SR, PC, format/vector
//   $2     6 words   + instruction address
//   $9    10 words   + instruction address, 4 internal words
//   $A    16 words   short bus fault
//   $B    46 words   long bus fault
// The internal words of the bus fault frames hold this core's resume state
// (resume kind/state, temporaries); handlers must leave them alone except
// for the SSW rerun bits and the data input buffer, as UM 8.2.2 says.  An
// instruction suspended at an access behind a failed posted write (resume
// kind "held") keeps that access in words 37-38 (address), 45 (size, R/W,
// FC, ...) and 22-23 (write data: the DIB of a write fault, which UM 8.2.2
// leaves to read faults).

function [31:0] frame_long_out;
	input [4:0] idx;
	begin
		case (idx)
			5'd0:  frame_long_out = {exc_throw ? (exc_sr | 16'h2000) : exc_sr, exc_pc[31:16]};   // throwaway: S set (UM 8.1.9)
			5'd1:  frame_long_out = {exc_pc[15:0], exc_fmt, 2'b00, exc_vec, 2'b00};
			default: begin
				if (exc_fmt == `FMT_SIXWORD || exc_fmt == `FMT_CPMID) begin
					case (idx)
						5'd2: frame_long_out = exc_fa;
						5'd3: frame_long_out = {tr_t1, tr_t0, flow, cp_cond, cp_dr, cp_ca, cp_pcbit, cp_trace_wait, cp_kind, cp_id, 1'b0, ir};
						default: frame_long_out = ea;
					endcase
				end else begin
					case (idx)
						5'd2:  frame_long_out = {exc_rk, 4'd0, exc_rs, exc_ssw};
						5'd3:  frame_long_out = {exc_stage_c, exc_stage_b};
						5'd4:  frame_long_out = exc_fa;
						5'd5:  frame_long_out = ea;
						5'd6:  frame_long_out = exc_dob;
						5'd7:  frame_long_out = src;
						5'd8:  frame_long_out = dst;
						5'd9:  frame_long_out = exc_baddr;
						5'd10: frame_long_out = 32'd0;
						// data input buffer; a suspended access keeps its write data there
						5'd11: frame_long_out = (exc_rk == RK_HELD) ? exc_dib : 32'd0;
						5'd12: frame_long_out = tmp;
						5'd13: frame_long_out = {ir, 4'h0, exc_dw_dst, exc_dw_ret};  // version 0
						5'd14: frame_long_out = tmp2;
						5'd15: frame_long_out = ea2;
						5'd16: frame_long_out = {exc_cnt, sub, mm_mask};
						5'd17: frame_long_out = {tmp3[15:0], ea_sel, imm_tgt, dw_reg, 1'b0, ea_pc, ea_ret};
						5'd18: frame_long_out = {exc_got, 5'd0, imm_ret, exc_partial[31:16]};
						5'd19: frame_long_out = {exc_partial[15:0], ext};
						5'd20: frame_long_out = {tr_t1, tr_t0, flow, cp_cond, cp_dr, cp_ca, cp_pcbit, cp_trace_wait, cp_kind, cp_id, 1'b0, cp_len, cp_pos};
						5'd21: frame_long_out = {2'd0, g_alu, g_size, g_srck, g_dstk, g_flags, g_wb, g_dreg, g_sext, g_bitop, g_move_mem, 1'b0, nx};
						5'd22: frame_long_out = {cp_resp, 5'd0, exc_held};
						default: frame_long_out = 32'd0;
					endcase
				end
			end
		endcase
	end
endfunction

// frame length in longwords per format
function [5:0] frame_lw;
	input [3:0] f;
	begin
		case (f)
			`FMT_SIXWORD: frame_lw = 6'd3;
			`FMT_CPMID:   frame_lw = 6'd5;
			`FMT_SHORTBUS: frame_lw = 6'd8;
			`FMT_LONGBUS: frame_lw = 6'd23;
			default: frame_lw = 6'd2;
		endcase
	end
endfunction
// ---- end core/ap030_frame.vh ----

//---------------------------------------------------------------------------
// tasks and helper functions
//---------------------------------------------------------------------------
// ---- begin core/ap030_funcs.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - helper functions (included by ap030_core.v at module level)

// rotates for register bit fields
function [31:0] rotr32; input [31:0] v; input [4:0] n;
	reg [31:0] s0, s1, s2, s3;
	begin
		s0     = n[0] ? {v[0],     v[31:1]}   : v;
		s1     = n[1] ? {s0[1:0],  s0[31:2]}  : s0;
		s2     = n[2] ? {s1[3:0],  s1[31:4]}  : s1;
		s3     = n[3] ? {s2[7:0],  s2[31:8]}  : s2;
		rotr32 = n[4] ? {s3[15:0], s3[31:16]} : s3;
	end
endfunction
function [31:0] rotl32; input [31:0] v; input [4:0] n;
	begin rotl32 = rotr32(v, 5'd0 - n); end
endfunction

// mask of the top w bits (w = 1..32)
function [31:0] topmask; input [5:0] w;
	begin topmask = (w >= 6'd32) ? 32'hFFFFFFFF : ~(32'hFFFFFFFF >> w); end endfunction

// leading zeros of a w-bit field held in the top bits [31 : 32-w] of msb_v (returns w when zero)
function [5:0] field_lz_msb; input [31:0] msb_v; input [5:0] w;
	integer i; reg found;
	begin
		field_lz_msb = w; found = 1'b0;
		for (i = 0; i < 32; i = i + 1) begin
			if (!found && (i[5:0] < w) && msb_v[31 - i]) begin field_lz_msb = i[5:0]; found = 1'b1; end
		end
	end
endfunction

// MOVEM: the next register to move (lowest set bit ascending, highest descending)
function [3:0] mm_next; input [15:0] m; input desc;
	integer i;
	begin
		mm_next = 4'd0;
		if (desc) begin for (i = 0; i < 16; i = i + 1) if (m[i]) mm_next = i[3:0]; end
		else begin for (i = 15; i >= 0; i = i - 1) if (m[i]) mm_next = i[3:0]; end
	end
endfunction

function [4:0] popcount16; input [15:0] m;
	integer i;
	begin popcount16 = 5'd0; for (i = 0; i < 16; i = i + 1) popcount16 = popcount16 + {4'd0, m[i]}; end
endfunction

// transfer size code for 1..4 bytes
function [1:0] sz_of_bytes; input [2:0] n;
	begin
		case (n)
			3'd1: sz_of_bytes = `SZ_B;
			3'd2: sz_of_bytes = `SZ_W;
			3'd3: sz_of_bytes = `SZ_3;
			default: sz_of_bytes = `SZ_L;
		endcase
	end
endfunction
function [2:0] bytes_of_sz; input [1:0] s;
	begin
		case (s)
			`SZ_B: bytes_of_sz = 3'd1;
			`SZ_W: bytes_of_sz = 3'd2;
			`SZ_3: bytes_of_sz = 3'd3;
			default: bytes_of_sz = 3'd4;
		endcase
	end
endfunction
// SSW SIZE field (SIZ encoding) to the internal size code
function [1:0] sz_of_siz; input [1:0] siz;
	begin
		case (siz)
			`SIZ_BYTE: sz_of_siz = `SZ_B;
			`SIZ_WORD: sz_of_siz = `SZ_W;
			`SIZ_3BYTE: sz_of_siz = `SZ_3;
			default: sz_of_siz = `SZ_L;
		endcase
	end
endfunction

// MMU instruction function code field (PRM PFLUSH/PLOAD/PTEST): 10xxx immediate,
// 01ddd Dn, 00000 SFC, 00001 DFC; the caller supplies Dn
function [2:0] mmu_fc; input [4:0] f; input [2:0] dn;
	begin
		if (f[4]) mmu_fc = f[2:0];
		else if (f[3]) mmu_fc = dn;
		else if (f[0]) mmu_fc = dfc;
		else mmu_fc = sfc;
	end
endfunction
// any other value (11xxx, 0001x-0011x) is not a supported encoding and takes
// the F-line exception (UM 9.8; the UM 3.3.3 descriptions list only these;
// WinUAE mmu_op30_helper_get_fc rejects 11xxx too)
function mmu_fc_ok; input [4:0] f;
	begin mmu_fc_ok = (f[4] && !f[3]) || (f[3] && !f[4]) || (f[4:1] == 4'd0); end endfunction

// coprocessor "valid EA" categories (UM Table 10-4) against ir[5:0]
function cp_ea_ok; input [2:0] cat;
	begin
		case (cat)
			3'b000: cp_ea_ok = ir_ea_ctrlalt;
			3'b001: cp_ea_ok = ir_ea_dataalt;
			3'b010: cp_ea_ok = ir_ea_memalt;
			3'b011: cp_ea_ok = ir_ea_alt;
			3'b100: cp_ea_ok = ir_ea_ctrl;
			3'b101: cp_ea_ok = ir_ea_data;
			3'b110: cp_ea_ok = ir_ea_mem | ir_ea_imm;   // memory includes immediate (MC68030 UM table 10-4)
			default: cp_ea_ok = ir_ea_any;
		endcase
	end
endfunction
// ---- end core/ap030_funcs.vh ----
// ---- begin core/ap030_tasks.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - sequencer tasks (included by ap030_core.v)
//
// All tasks are called from the clocked sequencer block and use
// nonblocking assignments; the pipe commands (pop_n, flush_req) are
// blocking per-clock variables consumed at the end of the block.

// data access: the result goes to dw_dst, execution continues at dw_ret
task dreq;
	input [31:0] addr;
	input  [1:0] size;
	input        rw;
	input [31:0] wdata;
	input  [2:0] fc;
	input        rmc;
	input        rmc_last;
	input  [3:0] dst_sel;
	input  [7:0] ret;
	begin
		d_stb <= 1'b1;
		d_addr <= addr; d_size <= size; d_rw <= rw; d_wdata <= wdata; d_fc <= fc;
		d_rmc <= rmc; d_rmc_last <= rmc_last; d_iack <= 1'b0; d_nocache <= 1'b0;
		dw_dst <= dst_sel; dw_ret <= ret;
		state <= S_DWAIT;
	end
endtask

// Complete an effective address and launch a generic operand read in the
// same clock. The read uses this address and the EA's program/data space;
// ea and ea_pc are still being registered, so neither is read back here.
task ea_ready;
 input [31:0] addr;
 begin
  ea <= addr;
  if (ea_ret == S_GEN_RD)
   dreq(addr, g_size, 1'b1, 32'd0,
        (ea_pcrel && PCREL_PROGRAM_SPACE) ? fc_prog : fc_data,
        1'b0, 1'b0, (g_srck == SK_EA) ? DW_SRC : DW_DST,
        g_move_mem ? S_MOVE_DEA : nx);
  else if (ea_ret == S_MOVE_WR) begin
   // MOVE's source and ALU controls are already registered. Its store
   // and flags can be issued with the completed destination address.
   sr[4:0] <= alu_f;
   finish;
   wr(addr, g_size, src, S_FETCH);
  end else if (ea_ret == S_LEA) begin
   wreg({1'b1, ir[11:9]}, addr);
   finish;
  end else state <= ea_ret;
 end
endtask

// convenience wrappers
task rd;   input [31:0] addr; input [1:0] size; input [3:0] dst_sel; input [7:0] ret;
	begin dreq(addr, size, 1'b1, 32'd0, (ea_pc && PCREL_PROGRAM_SPACE) ? fc_prog : fc_data, 1'b0, 1'b0, dst_sel, ret); end endtask
task wr;   input [31:0] addr; input [1:0] size; input [31:0] data; input [7:0] ret;
	begin dreq(addr, size, 1'b0, data, fc_data, 1'b0, 1'b0, DW_NONE, ret); end endtask
task rd_sd; input [31:0] addr; input [1:0] size; input [3:0] dst_sel; input [7:0] ret;   // supervisor data
	begin dreq(addr, size, 1'b1, 32'd0, `FC_SUPER_DATA, 1'b0, 1'b0, dst_sel, ret); end endtask
task wr_sd; input [31:0] addr; input [1:0] size; input [31:0] data; input [7:0] ret;
	begin dreq(addr, size, 1'b0, data, `FC_SUPER_DATA, 1'b0, 1'b0, DW_NONE, ret); end endtask
// coprocessor interface register access (CPU space type 2)
task cir_rd; input [4:0] off; input [1:0] size; input [3:0] dst_sel; input [7:0] ret;
	begin dreq(cp_base | {27'd0, off}, size, 1'b1, 32'd0, `FC_CPU_SPACE, 1'b0, 1'b0, dst_sel, ret); end endtask
task cir_wr; input [4:0] off; input [1:0] size; input [31:0] data; input [7:0] ret;
	begin dreq(cp_base | {27'd0, off}, size, 1'b0, data, `FC_CPU_SPACE, 1'b0, 1'b0, DW_NONE, ret); end endtask

// register write (full 32 bits)
// A7 means the stack pointer selected by S and M now, when the write is
// issued; the register file commits a clock later, after a same-clock SR
// change (RTE) has already switched stacks
task wreg; input [3:0] idx; input [31:0] val;
	begin
		rf_we <= 1'b1; rf_waddr <= idx; rf_wdata <= val;
		rf_wact <= !sr_s ? 2'd0 : (sr_m ? 2'd2 : 2'd1);
		if (state == S_GEN_EXEC || state == S_MOVEM1 || state == S_DBCC) begin
			byp_we = 1'b1; byp_reg = idx; byp_data = val;
		end
	end endtask
// register write merged by size (old value supplied)
task wreg_sz; input [3:0] idx; input [31:0] old; input [31:0] val; input [1:0] sz;
	begin wreg(idx, merge(old, val, sz)); end endtask

// control register read/write (shared by MOVEC and cpCTRL)
function [32:0] ctrl_rd;
	input [11:0] sel;
	begin
		case (sel)
			12'h000: ctrl_rd = {1'b0, 29'd0, sfc};
			12'h001: ctrl_rd = {1'b0, 29'd0, dfc};
			12'h002: ctrl_rd = {1'b0, cacr};
			12'h800: ctrl_rd = {1'b0, usp_q};
			12'h801: ctrl_rd = {1'b0, vbr};
			12'h802: ctrl_rd = {1'b0, caar};
			12'h803: ctrl_rd = {1'b0, msp_q};
			12'h804: ctrl_rd = {1'b0, isp_q};
			default: ctrl_rd = {1'b1, 32'd0};
		endcase
	end
endfunction

task ctrl_wr;
	input [11:0] sel;
	input [31:0] wval;
	begin
		case (sel)
			12'h000: sfc <= wval[2:0];
			12'h001: dfc <= wval[2:0];
			12'h002: begin
				cacr <= wval & `CACR_RDMASK;
				cacr_ci <= wval[`CACR_CI]; cacr_cei <= wval[`CACR_CEI];
				cacr_cd <= wval[`CACR_CD]; cacr_ced <= wval[`CACR_CED];
			end
			12'h800: begin sp_we <= 1'b1; sp_sel <= 2'd0; sp_wdata <= wval; end
			12'h801: vbr <= wval;
			12'h802: caar <= wval;
			12'h803: begin sp_we <= 1'b1; sp_sel <= 2'd2; sp_wdata <= wval; end
			default: begin sp_we <= 1'b1; sp_sel <= 2'd1; sp_wdata <= wval; end
		endcase
	end
endtask

// instruction complete: trace disposition, back to the boundary
task finish;
	begin
		trace_pend <= tr_t1 | (tr_t0 & flow);
		state <= S_FETCH;
	end
endtask

// instruction complete with same-clock dispatch when no boundary event waits
task finish_dispatch;
	begin
		if (!tr_t1 && !(tr_t0 & flow) && !irq_pend && !late_fault_pend && !stopped &&
		    w0_v && !w0_f && !(dc_needs_ext && (!w1_v || w1_f)))
			disp_req = 1'b1;
		else
			finish;
	end
endtask

// change of flow to a new PC: flush the pipe (address error on odd)
task go_pc;
	input [31:0] npc;
	begin
		flow <= 1'b1;
		if (npc[0]) begin
			exc_addr_err(npc);
		end else begin
			flush_req = 1'b1;
			flush_pc = npc;
			trace_pend <= tr_t1 | tr_t0;
			state <= S_FETCH;
		end
	end
endtask

// generic exception entry (UM 8.1): the frame fields are captured here
task exc_go;
	input  [7:0] vec;
	input  [3:0] fmt;
	input [31:0] pcv;
	input [31:0] iav;
	begin
		exc_vec <= vec; exc_fmt <= fmt; exc_pc <= pcv;
		if (fmt == `FMT_SIXWORD || fmt == `FMT_CPMID) exc_fa <= iav;
		exc_sr <= sr;
		exc_is_irq <= 1'b0; exc_throw <= 1'b0; exc_late <= 1'b0;
		exc_busfault <= (vec == `VEC_BUSERR) || (vec == `VEC_ADDRERR);
		// A trace pending for an instruction whose own exception is part of
		// its execution is taken after that exception's processing (UM 8.1.4,
		// 8.1.12 Table 8-5): TRAP #n, TRAPcc/TRAPV/cpTRAPcc, CHK/CHK2 and divide
		// by zero (instruction traps, traced in both trace modes, UM 8.1.7),
		// and a coprocessor post-instruction exception (UM 10.5.2.5).  Decided
		// by the instruction, not the vector: an interrupt or a coprocessor
		// can supply any vector, and a pre-instruction exception (not
		// executed) or a mid-instruction one (resumed) has no trace now
		trace_after_exc <= (vec != `VEC_BUSERR) &&
		                   (((state == S_TRAP || state == S_TRAPCC || state == S_CHK || state == S_CHK2_2 ||
		                      state == S_DIVZ || state == S_CPTRAP2) && (tr_t1 | tr_t0)) ||
		                    (state == S_CP_EXC && sub[1:0] == 2'd2 && (tr_t1 | cp_trace_wait)));
		trace_pend <= 1'b0;
		if (vec == `VEC_BUSERR || vec == `VEC_ADDRERR || vec == `VEC_SPURIOUS || vec == `VEC_FLINE ||
		    (vec >= `VEC_AUTOVEC && vec < `VEC_TRAP)) status_cnt <= 2'd3;
		// a bus/address error stacks its frame after the posted writes
		// before it (see the posted write faults in ap030_core.v)
		state <= (((vec == `VEC_BUSERR) || (vec == `VEC_ADDRERR)) && d_wpend) ? S_EXCW : S_EXC0;
	end
endtask

// pre-instruction exceptions (illegal, privilege, A/F-line): PC = instruction
task exc_pre; input [7:0] vec;
	begin exc_go(vec, `FMT_NORMAL, pc_i, 32'd0); end endtask
// post-instruction six-word frame (TRAPcc, CHK, divide by zero, MMU config): PC = next instruction
task exc_post; input [7:0] vec;
	begin exc_go(vec, `FMT_SIXWORD, scan_pc, pc_i); end endtask
task go_illegal; begin exc_pre(`VEC_ILLEGAL); end endtask
task go_priv;    begin exc_pre(`VEC_PRIV); end endtask

// stage images for the bus fault frames
task capture_pipe;
	begin
		exc_stage_c <= w0;
		exc_stage_b <= w1;
		exc_baddr <= scan_pc + 32'd2;
	end
endtask

// data access fault (from the memory system's fault record)
task exc_data_fault;
	input        boundary;      // at an instruction boundary (posted write): short frame
	input  [3:0] rkind;
	input  [7:0] rstate;
	begin
		capture_pipe;
		exc_fa <= f_addr;
		exc_dob <= f_dob;
		exc_got <= f_got;
		exc_partial <= f_partial;
		// SSW: FC FB RC RB 0 0 0 DF RM RW SIZE 0 FC2-FC0 (UM Figure 8-9)
		exc_ssw <= {1'b0, 1'b0, ~w0_v | w0_f, ~w1_v | w1_f, 3'b000, 1'b1, f_rm, f_rw, f_size, 1'b0, f_fc};
		exc_rk <= rkind; exc_rs <= rstate;
		exc_go(`VEC_BUSERR, boundary ? `FMT_SHORTBUS : `FMT_LONGBUS, boundary ? scan_pc : pc_i, 32'd0);
	end
endtask

// a posted write that failed, reported at a boundary from its record
task exc_late_fault;
	begin
		late_fault_pend <= 1'b0;
		d_unhold <= 1'b1;               // no access waits at a boundary
		capture_pipe;
		exc_fa <= lf_fa; exc_dob <= lf_dob;
		exc_got <= 3'd0; exc_partial <= 32'd0;
		exc_ssw <= {1'b0, 1'b0, ~w0_v | w0_f, ~w1_v | w1_f, 3'b000, lf_ssw};
		exc_rk <= RK_BOUNDARY; exc_rs <= S_FETCH;
		exc_go(`VEC_BUSERR, `FMT_SHORTBUS, scan_pc, 32'd0);
		exc_late <= 1'b1;
	end
endtask

// A posted write failed while the instruction in execution waits with its
// next data access, which has not reached the bus (the memory system holds
// it).  The bus error is taken now, mid-instruction: a long frame with the
// instruction's address as the PC, DF and the record of the failed write
// (UM 8.1.2, Table 8-6: "may not be the instruction that generated the
// faulted bus cycle").  The held access is dropped and kept in the frame;
// RTE reruns the write (DF set) and then issues it (S_RTE_HELD).
task exc_held_fault;
	begin
		late_fault_pend <= 1'b0;
		d_cancel <= 1'b1;
		capture_pipe;
		exc_fa <= lf_fa; exc_dob <= lf_dob;
		exc_got <= 3'd0;
		exc_partial <= d_addr;
		exc_dib <= d_wdata;
		exc_held <= {d_size, d_rw, d_fc, d_rmc, d_rmc_last, d_nocache, cpu_flt_ill, cpu_flt_fline};
		cpu_flt_ill <= 1'b0; cpu_flt_fline <= 1'b0;
		exc_ssw <= {1'b0, 1'b0, ~w0_v | w0_f, ~w1_v | w1_f, 3'b000, lf_ssw};
		exc_rk <= RK_HELD; exc_rs <= S_DWAIT;
		exc_go(`VEC_BUSERR, `FMT_LONGBUS, pc_i, 32'd0);
	end
endtask

// instruction stream fault: the word(s) needed are marked faulted
task exc_stream_fault;
	input need_b;      // the instruction also needed stage B
	input boundary;
	begin
		sf_req = 1'b1;
		sf_need_b = need_b;
		sf_boundary = boundary;
	end
endtask

// address error: prefetch from an odd address (UM 8.1.3)
task exc_addr_err;
	input [31:0] target;
	begin
		exc_stage_c <= 16'd0; exc_stage_b <= 16'd0;
		exc_baddr <= target + 32'd2;
		exc_fa <= 32'd0; exc_dob <= 32'd0; exc_got <= 3'd0; exc_partial <= 32'd0;
		exc_ssw <= {1'b0, 1'b0, 1'b1, 1'b1, 3'b000, 1'b0, 1'b0, 1'b1, 2'b00, 1'b0, fc_prog};
		exc_rk <= RK_BOUNDARY; exc_rs <= S_FETCH;
		exc_go(`VEC_ADDRERR, `FMT_LONGBUS, pc_i, 32'd0);
	end
endtask

// pop k words of the pipe (the caller checked they are present)
task pop; input [1:0] k; begin pop_n = k; end endtask

// consume an immediate/extension longword or word into imm (sign extended
// when asked); returns 0 when the words are not there yet or faulted
function pipe_ready;
	input two;
	begin
		pipe_ready = two ? have2 : w0_v;
	end
endfunction
function pipe_faulted;
	input two;
	begin
		pipe_faulted = two ? ((w0_v & w0_f) | (w1_v & w1_f) | (w0_v & !w0_f & w1_v & w1_f)) : (w0_v & w0_f);
	end
endfunction

// dispatch the next instruction from pq[0]
task dispatch;
	begin
		dbg_inst <= 1'b1;
		ir <= w0;
		ext <= w1;
		pc_i <= scan_pc;
		pop(dc_needs_ext ? 2'd2 : 2'd1);
		tr_t1 <= sr[`SR_T1];
		tr_t0 <= sr[`SR_T0];
		flow <= 1'b0;
		ea_sel <= 1'b0;
		ea_pc <= 1'b0;
		imm_tgt <= 1'b0;
		status_cnt <= 2'd1;
		// generic-path controls, so the decoder can look at the next word
		// while this instruction executes
		g_alu <= dc_alu; g_size <= dc_size; g_srck <= dc_srck; g_dstk <= dc_dstk; g_dreg <= dc_dreg;
		g_flags <= dc_flags; g_wb <= dc_wb; g_sext <= dc_sext; g_bitop <= dc_bitop;
		g_move_mem <= dc_move_mem;
		nx <= dc_first;
		// register operands (with the bypass of a write applied this clock)
		if (dc_srck == SK_REG) src <= (byp_we && byp_reg == dc_sreg) ? byp_data : rf_d;
		else if (dc_srck == SK_QUICK) src <= dc_quick;
		if (dc_dstk == DK_REG) dst <= (byp_we && byp_reg == dc_dreg) ? byp_data : rf_e;
		// exceptions detected at dispatch stack this instruction's address,
		// which is scan_pc in this clock (pc_i is being updated)
		if (dc_illegal) begin
			if (w0[15:12] == 4'hA) exc_go(`VEC_ALINE, `FMT_NORMAL, scan_pc, 32'd0);
			else if (w0[15:12] == 4'hF) begin
				if (!sr_s && w0[11:9] == 3'd0) exc_go(`VEC_PRIV, `FMT_NORMAL, scan_pc, 32'd0);
				else exc_go(`VEC_FLINE, `FMT_NORMAL, scan_pc, 32'd0);
			end else exc_go(`VEC_ILLEGAL, `FMT_NORMAL, scan_pc, 32'd0);
		end else if (dc_priv && !sr_s) begin
			exc_go(`VEC_PRIV, `FMT_NORMAL, scan_pc, 32'd0);
		end else if (dc_srck == SK_IMM) begin
			state <= S_IMM;
			imm_ret <= dc_move_mem ? S_MOVE_DEA : (dc_dstk == DK_EA) ? S_EA : (dc_dstk == DK_IMM) ? S_IMM : dc_first;
			ea_ret <= dc_dstrd ? S_GEN_RD : dc_first;
		end else if (dc_srck == SK_EA) begin
			state <= S_EA;
			ea_ret <= S_GEN_RD;
		end else if (dc_dstk == DK_EA) begin
			if (dc_move_mem) begin ea_sel <= 1'b1; ea_ret <= S_MOVE_WR; state <= S_EA; end
			else begin state <= S_EA; ea_ret <= dc_dstrd ? S_GEN_RD : dc_first; end
		end else if (dc_dstk == DK_IMM) begin
			state <= S_IMM; imm_tgt <= 1'b1; imm_ret <= dc_first;
		end else if (dc_eaonly) begin
			state <= S_EA; ea_ret <= dc_first;
		end else begin
			state <= dc_first;
		end
	end
endtask
// ---- end core/ap030_tasks.vh ----

// the dispatch reads the operands of the instruction being decoded
assign ra_d = dc_sreg;
assign ra_e = dc_dreg;

//---------------------------------------------------------------------------
// ALU operand selection
//---------------------------------------------------------------------------
always @* begin
	`ALU_SET(g_alu, g_size,
	         g_sext ? sext_sz(src, g_size) :
	         (g_bitop ? ((g_dstk == DK_REG) ? {27'd0, src[4:0]} : {29'd0, src[2:0]}) : src),
	         dst, src[5:0])
	case (state)
		S_PACK3:   `ALU_SET(g_alu, g_size, src, dst, 6'd0)
		S_TAS2:    `ALU_SET(`ALU_TAS, `SZ_B, src, dst, 6'd0)
		S_CAS1:    `ALU_SET(`ALU_CMP, g_size, rf_a, dst, 6'd0)
		S_CAS2_4:  `ALU_SET(`ALU_CMP, g_size, rf_a, src, 6'd0)
		S_CAS2_5:  `ALU_SET(`ALU_CMP, g_size, rf_a, dst, 6'd0)
		default: ;
	endcase
end

//---------------------------------------------------------------------------
// the sequencer
//---------------------------------------------------------------------------
integer k;
always @(posedge clk) if (ce) begin
	// per-clock defaults
	// The memory system samples this address only with i_stb. Prepare the
	// sequential payload independently of the late fetch/lazy-model decision,
	// keeping that decision off the address register's enable path.
	i_addr <= fetch_pc;
	pop_n = 2'd0;
	flush_req = 1'b0;
	flush_pc = 32'd0;
	pipe_load = 1'b0;
	pipe_c = 16'd0;
	pipe_b = 16'd0;
	pipe_c_v = 1'b0;
	pipe_b_v = 1'b0;
	disp_req = 1'b0;
	sf_req = 1'b0;
	sf_need_b = 1'b0;
	sf_boundary = 1'b0;
	byp_we = 1'b0;
	byp_reg = 4'd0;
	byp_data = 32'd0;
	rf_we <= 1'b0;
	sp_we <= 1'b0;
	d_stb <= 1'b0;
	d_rmc_release <= 1'b0;
	d_cancel <= 1'b0;
	d_unhold <= 1'b0;
	i_stb <= 1'b0;
	op_req <= 1'b0;
	dbg_inst <= 1'b0;
	tm_md <= 2'd0;
	tm_flush <= 1'b0;
	reg_we <= 1'b0;
	cacr_ci <= 1'b0; cacr_cei <= 1'b0; cacr_cd <= 1'b0; cacr_ced <= 1'b0;
	md_start <= 1'b0;
	irq_taken7 <= 1'b0;
	refill_p <= 1'b1;
	status_p <= ~((status_cnt != 2'd0) | halted_r);
	if (status_cnt != 2'd0) status_cnt <= status_cnt - 2'd1;

	if (rst) begin
		tm_pop <= 2'd0;
		state <= S_RESET0;
		sr <= `SR_RESET;
		vbr <= 32'd0;
		cacr <= 32'd0;
		caar <= 32'd0;
		sfc <= 3'd0; dfc <= 3'd0;
		pq_v <= 6'd0; pq_f <= 6'd0; pq_n <= 3'd0;
		scan_pc <= 32'd0; fetch_pc <= 32'd0; fetch_skip <= 1'b0; fetch_out <= 2'd0;
		fetch_disc <= 2'd0; fetch_hold <= 1'b1; stop_wait <= 6'd0; due_v <= 1'b0;
		trace_pend <= 1'b0; late_fault_pend <= 1'b0;
		lf_fa <= 32'd0; lf_dob <= 32'd0; lf_ssw <= 9'd0; exc_late <= 1'b0;
		exc_held <= 11'd0; d_cancel <= 1'b0; d_unhold <= 1'b0;
		stopped <= 1'b0; halted_r <= 1'b0; status_p <= 1'b1;
		reset_drive <= 1'b0; rst_cnt <= 10'd0;
		ipend_r <= 1'b0;
		exc_busfault <= 1'b1;          // faults during the reset sequence halt (UM 8.1.1)
		exc_is_irq <= 1'b0; exc_throw <= 1'b0;
		trace_after_exc <= 1'b0;
		cp_trace_wait <= 1'b0;
		status_cnt <= 2'd3;
		d_addr <= 32'd0; d_size <= 2'd0; d_rw <= 1'b1; d_rmc <= 1'b0; d_rmc_last <= 1'b0; d_iack <= 1'b0;
		d_nocache <= 1'b0;
		d_fc <= 3'd0; d_wdata <= 32'd0;
		i_addr <= 32'd0; i_fc <= 3'd0;
		ir <= 16'd0; ext <= 16'd0; pc_i <= 32'd0; ea <= 32'd0; ea2 <= 32'd0;
		src <= 32'd0; dst <= 32'd0; tmp <= 32'd0; tmp2 <= 32'd0; tmp3 <= 17'd0;

		cnt <= 8'd0; sub <= 8'd0; mm_mask <= 16'd0; ea_sel <= 1'b0; ea_pc <= 1'b0; ea_ret <= S_FETCH; imm_ret <= S_FETCH;
		imm_tgt <= 1'b0; dw_dst <= DW_NONE; dw_ret <= S_FETCH; dw_reg <= 4'd0;
		tr_t1 <= 1'b0; tr_t0 <= 1'b0; flow <= 1'b0;
		exc_vec <= 8'd0; exc_fmt <= 4'd0; exc_pc <= 32'd0; exc_sr <= 16'd0; exc_ssw <= 16'd0;
		exc_rk <= 4'd0; exc_rs <= 8'd0; exc_sp <= 32'd0; exc_ilvl <= 3'd0;
		exc_cnt <= 8'd0; exc_dw_dst <= 4'd0; exc_dw_ret <= 8'd0;
		exc_stage_c <= 16'd0; exc_stage_b <= 16'd0; exc_baddr <= 32'd0; exc_fa <= 32'd0; exc_dob <= 32'd0;
		exc_dib <= 32'd0; exc_got <= 3'd0; exc_partial <= 32'd0; rte_ver_err <= 1'b0;
		g_alu <= 6'd0; g_size <= 2'd0; g_srck <= 2'd0; g_dstk <= 2'd0; g_dreg <= 4'd0; g_flags <= 1'b0; g_wb <= 1'b0;
		g_sext <= 1'b0; g_bitop <= 1'b0; g_move_mem <= 1'b0; nx <= S_FETCH;
		rte_fake <= 1'b0; rerun_merge <= 1'b0; exc_active <= 1'b0;
		cpu_flt_ill <= 1'b0; cpu_flt_fline <= 1'b0; iack_pc_i <= 1'b0; iack_cpmid <= 1'b0;
		cp_id <= 3'd0; cp_resp <= 16'd0; cp_cond <= 1'b0; cp_len <= 8'd0; cp_pos <= 8'd0; cp_dr <= 1'b0;
		cp_ca <= 1'b0; cp_pcbit <= 1'b0; cp_kind <= 4'd0;
		md_div <= 1'b0; md_sign <= 1'b0; md_a <= 32'd0; md_hi <= 32'd0; md_lo <= 32'd0;
		op_kind <= 3'd0; op_level <= 3'd0; op_la <= 32'd0; op_fc <= 3'd0; op_fcmask <= 3'd0;
		reg_sel <= 3'd0; reg_wdata_hi <= 32'd0; reg_wdata_lo <= 32'd0; reg_fd <= 1'b0;
		rf_waddr <= 4'd0; rf_wact <= 2'd1; rf_wdata <= 32'd0; sp_sel <= 2'd0; sp_wdata <= 32'd0;
	end else begin
		//---------------------------------------------------------- events from the memory system
		// (a failed posted write, d_late_fault, is handled after the states)
		ipend_r <= irq_pend && !exc_is_irq_active;

		//---------------------------------------------------------- the states
// ---- begin core/ap030_exec.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - sequencer state bodies (included inside the clocked block)
case (state)
// ---- begin core/ap030_exec_a.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - states part A: boundary, data wait, immediates, effective
// addresses, the generic read-operate-write path, MOVE, program flow,
// linkage, and the simpler special instructions

//-------------------------------------------------------------- reset (UM 8.1.1)
S_RESET0: begin
	exc_active <= 1'b1; exc_busfault <= 1'b1;
	status_cnt <= 2'd3;
	dreq(32'd0, `SZ_L, 1'b1, 32'd0, `FC_SUPER_PROG, 1'b0, 1'b0, DW_TMP, S_RESET1);
end
S_RESET1: begin
	sp_we <= 1'b1; sp_sel <= 2'd1; sp_wdata <= tmp;
	dreq(32'd4, `SZ_L, 1'b1, 32'd0, `FC_SUPER_PROG, 1'b0, 1'b0, DW_TMP, S_RESET2);
end
S_RESET2: begin
	exc_busfault <= 1'b0; exc_active <= 1'b0; fetch_hold <= 1'b0;
	pc_i <= tmp;
	if (tmp[0]) begin halted_r <= 1'b1; state <= S_HALT; end
	else begin flush_req = 1'b1; flush_pc = tmp; state <= S_FETCH; end
end
S_HALT: begin
	halted_r <= 1'b1;
end

//-------------------------------------------------------------- instruction boundary
S_FETCH: begin
	if (late_fault_pend) begin
		exc_late_fault;
	end else if (trace_pend) begin
		trace_pend <= 1'b0;
		status_cnt <= 2'd2;
		exc_go(`VEC_TRACE, `FMT_SIXWORD, scan_pc, pc_i);
	end else if (irq_pend) begin
		// not while a posted write is outstanding: it may be the one that withdraws the
		// request (an interrupt mask register written just before the SR is lowered),
		// and the acknowledge it would leave behind finds no source: a spurious interrupt
		if (!d_wpend) begin
			stopped <= 1'b0;
			status_cnt <= 2'd2;
			exc_ilvl <= irq_lvl;
			state <= S_IACK;
		end
	end else if (stopped) begin
		// STOP: wait for an interrupt (UM 8.1.7 / PRM STOP)
	end else if (w0_v) begin
		if (w0_f) exc_stream_fault(1'b0, 1'b1);
		else if (dc_needs_ext && !w1_v) ;                    // second word not yet here
		else if (dc_needs_ext && w1_f) exc_stream_fault(1'b1, 1'b1);
		else disp_req = 1'b1;
	end
end

//-------------------------------------------------------------- interrupt acknowledge (UM 7.4.1)
S_IACK: begin
	d_stb <= 1'b1; d_iack <= 1'b1;
	d_addr <= {28'hFFFFFFF, 1'b1, exc_ilvl}; d_addr[0] <= 1'b1; d_addr[3:1] <= exc_ilvl;
	d_size <= `SZ_B; d_rw <= 1'b1; d_fc <= `FC_CPU_SPACE; d_rmc <= 1'b0; d_rmc_last <= 1'b0; d_wdata <= 32'd0;
	dw_dst <= DW_TMP; dw_ret <= S_EXC0;
	ipend_r <= 1'b0;
	state <= S_DWAIT;
end

//-------------------------------------------------------------- data access wait
S_DWAIT: begin
	if (d_iack && (d_ack || d_iack_berr)) begin
		// interrupt vector: supplied, autovector, or spurious (bus error)
		d_iack <= 1'b0;
		// a coprocessor busy/not-ready service stacks the instruction's own
		// address so that it restarts (UM 10.4.3); a come-again null
		// primitive with IA stacks a coprocessor mid-instruction frame, whose
		// RTE reads the response CIR again (UM 10.4.8); otherwise the next one
		exc_go(d_iack_berr ? `VEC_SPURIOUS : (d_avec ? (`VEC_AUTOVEC + {5'd0, exc_ilvl}) : d_rdata[7:0]),
		       iack_cpmid ? `FMT_CPMID : `FMT_NORMAL, iack_pc_i ? pc_i : scan_pc, iack_cpmid ? pc_i : 32'd0);
		iack_pc_i <= 1'b0;
		iack_cpmid <= 1'b0;
		exc_is_irq <= 1'b1;
		if (exc_ilvl == 3'd7) irq_taken7 <= 1'b1;
	end else if (rte_fake || d_ack) begin : deliver
		reg [31:0] data;
		reg  [1:0] dsz;
		data = rte_fake ? exc_dib : d_rdata;
		dsz  = d_size;
		if (rerun_merge) begin
			// UM 8.2.1: a rerun of the second portion completes the operand;
			// the rerun moves the SSW SIZE bytes, the operand is those plus
			// the bytes already read
			data = (exc_partial << (8 * bytes_of_sz(sz_of_siz(exc_ssw[5:4])))) | data;
			dsz  = sz_of_bytes(exc_got + bytes_of_sz(sz_of_siz(exc_ssw[5:4])));
			rerun_merge <= 1'b0;
		end
		rte_fake <= 1'b0;
		case (dw_dst)
			DW_SRC:  src <= data;
			DW_DST:  dst <= data;
			DW_TMP:  tmp <= data;
			DW_TMP2: tmp2 <= data;
			DW_EA:   ea <= data;
			DW_REG:  wreg(dw_reg, merge(dst, data, dsz));
			DW_REGL: wreg(dw_reg, sext_sz(data, dsz));
			DW_SR:   sr <= data[15:0] & `SR_MASK;
			DW_FRAME: begin
				cnt <= cnt + 8'd1;
				case (cnt[4:0])
					5'd2: if (exc_fmt == `FMT_CPMID) pc_i <= data;
					      else begin
					      	exc_rk <= (exc_fmt == `FMT_SHORTBUS) ? RK_BOUNDARY : data[31:28];
					      	exc_rs <= data[23:16];
					      	exc_ssw <= data[15:0];
					      end
					5'd3: if (exc_fmt == `FMT_CPMID) begin
					      	{cp_cond, cp_dr, cp_ca, cp_pcbit, cp_trace_wait, cp_kind, cp_id} <= data[28:17];
					      	ir <= data[15:0];
					      end else begin
					      	exc_stage_c <= data[31:16];
					      	exc_stage_b <= data[15:0];
					      end
					5'd4: if (exc_fmt == `FMT_CPMID) ea <= data;
					      else exc_fa <= data;
					5'd5: ea <= data;
					5'd6: exc_dob <= data;
					5'd7: src <= data;
					5'd8: dst <= data;
					5'd9: exc_baddr <= data;
					5'd11: exc_dib <= data;
					5'd12: tmp <= data;
					5'd13: begin
						ir <= data[31:16];
						rte_ver_err <= (data[15:12] != 4'h0);
						exc_dw_dst <= data[11:8]; exc_dw_ret <= data[7:0];
					end
					5'd14: tmp2 <= data;
					5'd15: ea2 <= data;
					5'd16: begin
						exc_cnt <= data[31:24]; sub <= data[23:16];
						mm_mask <= data[15:0];
					end
					5'd17: begin
						tmp3 <= {1'b0, data[31:16]};

						{ea_sel, imm_tgt, dw_reg} <= data[15:10];
						ea_pc <= data[8]; ea_ret <= data[7:0];
					end
					5'd18: begin
						exc_got <= data[31:29]; imm_ret <= data[23:16];
						exc_partial[31:16] <= data[15:0];
					end
					5'd19: begin
						exc_partial[15:0] <= data[31:16];
						ext <= data[15:0];
					end
					5'd20: begin
						{tr_t1, tr_t0, flow, cp_cond, cp_dr, cp_ca, cp_pcbit, cp_trace_wait, cp_kind, cp_id} <= data[31:17];
						{cp_len, cp_pos} <= data[15:0];
					end
					5'd21: begin
						{g_alu, g_size, g_srck, g_dstk, g_flags, g_wb} <= data[29:16];
						{g_dreg, g_sext, g_bitop, g_move_mem} <= data[15:9];
						nx <= data[7:0];
					end
					5'd22: begin
						cp_resp <= data[31:16];
						exc_held <= data[10:0];
					end
					default: ;
				endcase
			end
			default: ;
		endcase
		if (dw_ret == S_MOVE_DEA) begin
			ea_sel <= 1'b1; ea_ret <= S_MOVE_WR; state <= S_EA;
		end else if (dw_ret == S_JMP && !ea[0]) begin
			go_pc(ea);
		end else state <= dw_ret;
	end else if (d_fault) begin
		if (exc_busfault) begin
			// UM 7.5.4: double bus fault
			halted_r <= 1'b1; state <= S_HALT;
		end else if (cpu_flt_ill) begin
			cpu_flt_ill <= 1'b0; exc_pre(`VEC_ILLEGAL);           // BKPT acknowledge terminated by BERR
		end else if (cpu_flt_fline) begin
			cpu_flt_fline <= 1'b0; exc_pre(`VEC_FLINE);           // no coprocessor answered (UM 10.5.2.8)
		end else if (exc_active) begin
			exc_data_fault(1'b1, RK_BOUNDARY, S_FETCH);
		end else begin
			// an RMW fault is rerun as a whole instruction, or the instruction
			// counts as emulated when DF is cleared (UM 8.2.2)
			exc_data_fault(1'b0, d_rmc ? RK_RMW : d_rw ? RK_READ : RK_WRITE, S_DWAIT);
		end
	end else if (d_held && late_fault_pend) begin
		// a posted write failed and this access waits behind it: suspend the
		// instruction here (UM 8.1.2); exception processing, the RTE's frame
		// loads and IACK cannot be suspended, they go on and the fault is
		// taken at the next boundary
		if (exc_active || exc_busfault || d_iack) d_unhold <= 1'b1;
		else exc_held_fault;
	end
end

//-------------------------------------------------------------- immediate operand
S_IMM: begin : imm_state
	reg two;
	two = !imm_tgt && (g_size == `SZ_L) && !g_bitop;
	if (!pipe_ready(two)) ;
	else if (pipe_faulted(two)) exc_stream_fault(two, 1'b0);
	else begin
		if (imm_tgt) dst <= {24'd0, w0[7:0]};
		else if (g_bitop) src <= {24'd0, w0[7:0]};      // bit number: one word, low byte
		else if (two) src <= {w0, w1};
		else if (g_size == `SZ_B) src <= {24'd0, w0[7:0]};
		else src <= {16'd0, w0};
		pop(two ? 2'd2 : 2'd1);
		imm_tgt <= 1'b1;
		if (imm_ret == S_MOVE_DEA) begin
			ea_sel <= 1'b1; ea_ret <= S_MOVE_WR; state <= S_EA;
		end else state <= imm_ret;
	end
end

//-------------------------------------------------------------- effective address (PRM 2.2)
S_EA: begin : ea_state
	reg [31:0] bytes;
	bytes = size_bytes(g_size, ea_regn == 3'd7);
	ea_pc <= ea_pcrel;          // the reads that follow use program space for PC-relative modes
	case (ea_mode)
		3'b010: begin ea_ready(rf_a); end
		3'b011: begin
			ea_ready(rf_a); wreg({1'b1, ea_regn}, rf_a + bytes);
			// a register destination that is this base register sees the update
			if (g_dstk == DK_REG && g_dreg == {1'b1, ea_regn}) dst <= rf_a + bytes;
		end
		3'b100: begin
			ea_ready(rf_a - bytes); wreg({1'b1, ea_regn}, rf_a - bytes);
			if (g_dstk == DK_REG && g_dreg == {1'b1, ea_regn}) dst <= rf_a - bytes;
			// MOVE An,-(An) stores the initial value of An: the source is read
			// before the destination address is formed (WinUAE 68030 cputest)
		end
		3'b101: begin
			if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
			else begin ea_ready(rf_a + sext16(w0)); pop(2'd1); end
		end
		3'b110: begin
			if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
			else if (!w0[8]) begin
				ea_ready(rf_a + sext8(w0[7:0]) + index_val(rf_c, w0));
				pop(2'd1);
			end else begin
				tmp <= w0[7] ? 32'd0 : rf_a;
				tmp2 <= w0[6] ? 32'd0 : index_val(rf_c, w0);
				sub <= w0[7:0];
				pop(2'd1); state <= S_EA_FULL;
			end
		end
		default: begin
			case (ea_regn)
				3'b000: begin
					if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
					else begin ea_ready(sext16(w0)); pop(2'd1); end
				end
				3'b001: begin
					if (!have2) ; else if (pipe_faulted(1'b1)) exc_stream_fault(1'b1, 1'b0);
					else begin ea_ready({w0, w1}); pop(2'd2); end
				end
				3'b010: begin
					if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
					else begin ea_ready(scan_pc + sext16(w0)); pop(2'd1); end
				end
				3'b011: begin
					if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
					else if (!w0[8]) begin
						ea_ready(scan_pc + sext8(w0[7:0]) + index_val(rf_c, w0));
						pop(2'd1);
					end else begin
						tmp <= w0[7] ? 32'd0 : scan_pc;
						tmp2 <= w0[6] ? 32'd0 : index_val(rf_c, w0);
						sub <= w0[7:0];
						pop(2'd1); state <= S_EA_FULL;
					end
				end
				default: begin
					// immediate as a destination address is meaningless; illegal
					go_illegal;
				end
			endcase
		end
	endcase
end

S_EA_FULL: begin : ea_full
	// base displacement per BD SIZE, then the indirection of PRM Table 2-2
	reg [31:0] bd;
	reg ok, flt, two;
	case (sub[5:4])
		2'b10: begin two = 1'b0; ok = w0_v; flt = w0_v & w0_f; bd = sext16(w0); end
		2'b11: begin two = 1'b1; ok = have2; flt = pipe_faulted(1'b1); bd = {w0, w1}; end
		default: begin two = 1'b0; ok = 1'b1; flt = 1'b0; bd = 32'd0; end
	endcase
	if (!ok) ;
	else if (flt) exc_stream_fault(two, 1'b0);
	else begin
		if (sub[5:4] == 2'b10) pop(2'd1);
		else if (sub[5:4] == 2'b11) pop(2'd2);
		if (sub[2:0] == 3'b000) begin
			ea_ready(tmp + bd + tmp2);
		end else begin
			// memory indirect: preindexed unless IS=1 or I/IS[2]=1 (postindexed)
			tmp <= tmp + bd + ((!sub[6] && !sub[2]) ? tmp2 : 32'd0);
			rd(tmp + bd + ((!sub[6] && !sub[2]) ? tmp2 : 32'd0), `SZ_L, DW_EA, S_EA_IND);
		end
	end
end

S_EA_IND: begin : ea_ind_blk
	// outer displacement per I/IS[1:0]; postindexing adds the index now
	reg [31:0] od;
	reg ok, flt, two;
	case (sub[1:0])
		2'b10: begin two = 1'b0; ok = w0_v; flt = w0_v & w0_f; od = sext16(w0); end
		2'b11: begin two = 1'b1; ok = have2; flt = pipe_faulted(1'b1); od = {w0, w1}; end
		default: begin two = 1'b0; ok = 1'b1; flt = 1'b0; od = 32'd0; end
	endcase
	if (!ok) ;
	else if (flt) exc_stream_fault(two, 1'b0);
	else begin
		if (sub[1:0] == 2'b10) pop(2'd1);
		else if (sub[1:0] == 2'b11) pop(2'd2);
		ea_ready(ea + od + ((!sub[6] && sub[2]) ? tmp2 : 32'd0));
	end
end

//-------------------------------------------------------------- generic path
S_GEN_EXEC: begin : gen_exec
	if (g_flags) sr[4:0] <= alu_f;
	if (g_dstk == DK_REG && g_wb) wreg(g_dreg, g_dreg[3] ? alu_r : merge(dst, alu_r, g_size));
	if (g_dstk == DK_EA && g_wb) begin
		finish;
		wr(ea, g_size, alu_r, S_FETCH);
	end else begin
		finish_dispatch;
	end
end
// (S_MOVE_DEA handled directly by dispatch / S_IMM / S_DWAIT)


//-------------------------------------------------------------- PEA
S_PEA: begin wreg(4'd15, rf_c - 32'd4); finish; wr(rf_c - 32'd4, `SZ_L, ea, S_FETCH); end

//-------------------------------------------------------------- Bcc / BRA / BSR
S_BCC: begin : bcc_state
	reg [31:0] target, ret;
	reg ok, flt, two;
	reg [1:0] npop;
	if (ir[7:0] == 8'h00) begin two = 1'b0; ok = w0_v; flt = w0_v & w0_f; target = scan_pc + sext16(w0); npop = 2'd1; end
	else if (ir[7:0] == 8'hFF) begin two = 1'b1; ok = have2; flt = pipe_faulted(1'b1); target = scan_pc + {w0, w1}; npop = 2'd2; end
	else begin two = 1'b0; ok = 1'b1; flt = 1'b0; target = scan_pc + sext8(ir[7:0]); npop = 2'd0; end
	ret = scan_pc + {29'd0, npop, 1'b0};
	if (!ok) ;
	else if (flt) exc_stream_fault(two, 1'b0);
	else if (ir[11:8] == 4'h1) begin
		// BSR: push the return address, then branch
		pop(npop);
		ea <= target;
		wreg(4'd15, rf_c - 32'd4);
		wr(rf_c - 32'd4, `SZ_L, ret, S_JMP);
	end else if (ir[11:8] == 4'h0 || cc_true(ir[11:8], sr[4:0])) begin
		pop(npop);
		go_pc(target);
	end else if (npop == 2'd0) begin
		finish_dispatch;
	end else begin
		pop(npop);
		finish;
	end
end

//-------------------------------------------------------------- JMP / JSR / RTS / RTR / RTD
// an odd target: the address error frame's PC is the instruction + 2 for
// JMP and the target for JSR (WinUAE gencpu, 68030 AE corpus v24)
S_JMP: begin
	go_pc(ea);
	// JMP: instruction + 2; the 68020+ index modes have already consumed
	// their extension words, so the end of the instruction + 2 for them
	if (ea[0] && ir[15:6] == 10'b0100_1110_11)
		exc_pc <= (ir[5:3] == 3'b110 || ir[5:0] == 6'b111011) ? scan_pc + 32'd2 : pc_i + 32'd2;
	if (ea[0] && ir[15:6] == 10'b0100_1110_10) exc_pc <= ea;             // JSR
end
S_JSR: begin
	wreg(4'd15, rf_c - 32'd4);
	wr(rf_c - 32'd4, `SZ_L, scan_pc, S_JMP);
end
S_RTS: rd(rf_c, `SZ_L, DW_TMP, S_RTS2);
S_RTS2: begin
	wreg(4'd15, rf_c + 32'd4);
	go_pc(tmp);
	if (tmp[0] && ir[2:0] == 3'd7) exc_pc <= pc_i + 32'd2;   // RTR: instruction + 2
end
S_RTR: rd(rf_c, `SZ_W, DW_TMP2, S_RTR2);
S_RTR2: begin
	sr[4:0] <= tmp2[4:0];
	wreg(4'd15, rf_c + 32'd2);
	rd(rf_c + 32'd2, `SZ_L, DW_TMP, S_RTS2);
end
S_RTD: begin
	// the displacement was popped with the opcode (ext)
	tmp2 <= sext16(ext);
	rd(rf_c, `SZ_L, DW_TMP, S_RTD2);
end
S_RTD2: begin wreg(4'd15, rf_c + 32'd4 + tmp2); go_pc(tmp); end

//-------------------------------------------------------------- DBcc / Scc / TRAPcc / TRAPV
S_DBCC: begin : dbcc_state
	// the displacement (ext) is relative to its own address, pc_i + 2
	reg [15:0] nw;
	nw = rf_a[15:0] - 16'd1;
	if (cc_true(ir[11:8], sr[4:0])) finish_dispatch;
	else begin
		wreg({1'b0, ir[2:0]}, {rf_a[31:16], nw});
		// the MC68020/030 prefetch from the branch target whenever the
		// condition is false, so an odd displacement is an address error
		// even when the count expires (WinUAE gencpu DBcc, 68030 AE corpus)
		if (nw != 16'hFFFF || ext[0]) begin
			go_pc(pc_i + 32'd2 + sext16(ext));
			if (ext[0]) exc_pc <= pc_i + 32'd2 + sext16(ext);   // the frame's PC is the target
		end
		else finish_dispatch;
	end
end
S_SCC: begin : scc_state
	reg [7:0] v;
	v = cc_true(ir[11:8], sr[4:0]) ? 8'hFF : 8'h00;
	if (ir[5:3] == 3'b000) begin wreg({1'b0, ir[2:0]}, {dst[31:8], v}); finish; end
	else begin finish; wr(ea, `SZ_B, {24'd0, v}, S_FETCH); end
end
S_TRAPCC: begin : trapcc_state
	reg [1:0] npop;
	reg ok, flt, two;
	if (ir[15:12] == 4'h4) begin npop = 2'd0; ok = 1'b1; flt = 1'b0; two = 1'b0; end       // TRAPV
	else if (ir[2:0] == 3'b010) begin npop = 2'd1; ok = w0_v; flt = w0_v & w0_f; two = 1'b0; end
	else if (ir[2:0] == 3'b011) begin npop = 2'd2; ok = have2; flt = pipe_faulted(1'b1); two = 1'b1; end
	else begin npop = 2'd0; ok = 1'b1; flt = 1'b0; two = 1'b0; end
	if (!ok) ;
	else if (flt) exc_stream_fault(two, 1'b0);
	else begin
		pop(npop);
		if (cc_true((ir[15:12] == 4'h4) ? 4'h9 : ir[11:8], sr[4:0]))
			exc_go(`VEC_TRAPCC, `FMT_SIXWORD, scan_pc + {29'd0, npop, 1'b0}, pc_i);
		else finish;
	end
end

//-------------------------------------------------------------- LINK / UNLK
S_LINK: begin : link_state
	// LINK.W: the displacement is ext; LINK.L: ext is its high word, the low word follows
	reg two;
	reg [31:0] disp;
	two = (g_size == `SZ_L);
	disp = two ? {ext, w0} : sext16(ext);
	if (two && !w0_v) ; else if (two && w0_f) exc_stream_fault(1'b0, 1'b0);
	else begin
		if (two) pop(2'd1);
		ea <= disp;
		tmp <= rf_c - 32'd4;
		// LINK A7 pushes the initial A7 on the 68020/030 (only the 68040
		// pushes the decremented value; WinUAE gencpu and 68030 cputest)
		wr(rf_c - 32'd4, `SZ_L, rf_a, S_LINK2);
	end
end
S_LINK2: begin
	if (ir[2:0] != 3'd7) begin
		wreg({1'b1, ir[2:0]}, tmp);
		sp_we <= 1'b1; sp_sel <= !sr_s ? 2'd0 : (sr_m ? 2'd2 : 2'd1); sp_wdata <= tmp + ea;
	end else begin
		wreg(4'd15, tmp + ea);
	end
	finish;
end
S_UNLK: begin tmp <= rf_a; dw_reg <= {1'b1, ir[2:0]}; rd(rf_a, `SZ_L, DW_REGL, S_UNLK2); end
S_UNLK2: begin if (ir[2:0] != 3'd7) wreg(4'd15, tmp + 32'd4); finish; end

//-------------------------------------------------------------- MOVE USP / from SR,CCR / to SR,CCR
S_MOVE_USP: begin
	if (ir[3]) wreg({1'b1, ir[2:0]}, usp_q);
	else begin sp_we <= 1'b1; sp_sel <= 2'd0; sp_wdata <= rf_a; end
	finish;
end
S_MOVE_FSR: begin : movefsr
	reg [15:0] v;
	v = (ir[11:9] == 3'b000) ? sr : {8'd0, sr[7:0]};
	if (ir[5:3] == 3'b000) begin wreg({1'b0, ir[2:0]}, {dst[31:16], v}); finish; end
	else begin finish; wr(ea, `SZ_W, {16'd0, v}, S_FETCH); end
end
S_MOVE_SR: begin : movesr
	reg [15:0] nsr;
	reg is_sr;
	is_sr = (ir[15:12] == 4'h4) ? ir[9] : ir[6];        // MOVE to SR ($46C0) / ORI etc. with word size
	case (g_alu)
		`ALU_OR:  nsr = sr | src[15:0];
		`ALU_AND: nsr = sr & src[15:0];
		`ALU_EOR: nsr = sr ^ src[15:0];
		default:  nsr = src[15:0];
	endcase
	// T0 traces ORI/ANDI/EORI to CCR and SR and MOVE to SR, whatever
	// they change; MOVE to CCR is not traced by T0 (WinUAE gencpu
	// check_trace, 68020/68030; 68030 corpus v24)
	if (!is_sr) begin
		sr[4:0] <= nsr[4:0];
		finish;
		if (ir[15:12] != 4'h4) trace_pend <= tr_t1 | tr_t0;
	end else begin
		sr <= nsr & `SR_MASK;
		// the program space may have changed: refill the pipe (UM 12.7.1)
		flush_req = 1'b1; flush_pc = scan_pc;
		trace_pend <= tr_t1 | tr_t0;
		state <= S_FETCH;
	end
end

//-------------------------------------------------------------- MOVEC (PRM)
S_MOVEC: begin : movec_state
	reg [32:0] cr;
	cr = ctrl_rd(ext[11:0]);
	if (cr[32]) go_illegal;
	else if (!ir[0]) begin
		wreg({ext[15], ext[14:12]}, cr[31:0]);
		finish;
	end else begin
		ctrl_wr(ext[11:0], rf_a);
		finish;
	end
end

//-------------------------------------------------------------- MOVES (PRM)
S_MOVES0: begin
	if (ext[11]) begin
		// register to <ea> in DFC space
		finish;
		dreq(ea, g_size, 1'b0, rf_a, dfc, 1'b0, 1'b0, DW_NONE, S_FETCH);
	end else begin
		dst <= rf_a;
		dw_reg <= {ext[15], ext[14:12]};
		dreq(ea, g_size, 1'b1, 32'd0, sfc, 1'b0, 1'b0, ext[15] ? DW_REGL : DW_REG, S_MOVES1);
	end
end
S_MOVES1: finish_dispatch;


//-------------------------------------------------------------- NOP / STOP / RESET / TRAP / BKPT
S_NOP: begin
	if (bus_quiet) finish;      // UM 7.6: NOP synchronizes with pending bus cycles
end
S_STOP: begin
	// the immediate SR value was popped with the opcode (ext)
	sr <= ext & `SR_MASK;
	// a traced STOP does not stop (UM 8.1.7)
	if (tr_t1 || (tr_t0 && ({ext[15:12], ext[10:8]} != {sr[15:12], sr[10:8]}))) trace_pend <= 1'b1;
	else stopped <= 1'b1;
	state <= S_FETCH;
end
S_RESETI: begin
	// UM 7.8: RESET drives the pin for 512 clocks; the CPU's own state is
	// untouched.  The bus is idle for the whole pulse (Figure 7-65: the
	// external devices are being reset): prefetching stops at once, and the
	// pin is driven once the fetches already requested have returned and
	// the posted writes have completed (bus_quiet); fetching resumes after.
	fetch_hold <= 1'b1;
	if (!reset_drive) begin
		if (fetch_hold && fetch_out == 2'd0 && bus_quiet) begin reset_drive <= 1'b1; rst_cnt <= 10'd511; end
	end else if (rst_cnt != 10'd0) rst_cnt <= rst_cnt - 10'd1;
	else begin reset_drive <= 1'b0; fetch_hold <= 1'b0; finish; end
end
S_TRAP: exc_go(`VEC_TRAP + {4'd0, ir[3:0]}, `FMT_NORMAL, scan_pc, 32'd0);
S_BKPT: begin
	// breakpoint acknowledge cycle (UM 7.4.2): CPU space type 0, number on A2-A4
	cpu_flt_ill <= 1'b1;
	dreq({27'd0, ir[2:0], 2'b00}, `SZ_W, 1'b1, 32'd0, `FC_CPU_SPACE, 1'b0, 1'b0, DW_TMP, S_BKPT2);
end
S_BKPT2: begin
	// the returned word replaces the BKPT in the pipe and executes
	cpu_flt_ill <= 1'b0;
	pipe_load = 1'b1; flush_pc = pc_i;
	pipe_c = tmp[15:0]; pipe_c_v = 1'b1;
	pipe_b = w0; pipe_b_v = w0_v & !w0_f;
	state <= S_FETCH;
end

//-------------------------------------------------------------- EXG
S_EXG: begin tmp <= rf_a; wreg(ra_a, rf_b); state <= S_EXG2; end
S_EXG2: begin wreg(ra_b, tmp); finish; end

//-------------------------------------------------------------- -(Ay),-(Ax) / (Ay)+,(Ax)+ forms and PACK/UNPK
// ABCD/SBCD/ADDX/SUBX -(Ay),-(Ax); CMPM (Ay)+,(Ax)+; PACK/UNPK -(Ay),-(Ax) or Dx,Dy
S_PACK: begin : pack_state
	reg [31:0] bs;       // source operand size in bytes
	reg is_pack, is_unpk, is_cmpm;
	is_pack = (ir[15:12] == 4'h8) && (ir[8:6] == 3'b101);
	is_unpk = (ir[15:12] == 4'h8) && (ir[8:6] == 3'b110);
	is_cmpm = (ir[15:12] == 4'hB);
	bs = is_pack ? 32'd2 : (is_unpk ? ((ir[2:0] == 3'd7) ? 32'd2 : 32'd1) : size_bytes(g_size, ir[2:0] == 3'd7));
	if (!ir[3]) begin
		// register form (PACK/UNPK Dx,Dy)
		src <= rf_a; dst <= rf_b; state <= S_PACK3;
	end else if (is_cmpm) begin
		wreg({1'b1, ir[2:0]}, rf_a + bs);
		rd(rf_a, g_size, DW_SRC, S_PACK2);
	end else begin
		wreg({1'b1, ir[2:0]}, rf_a - bs);
		rd(rf_a - bs, is_pack ? `SZ_W : (is_unpk ? `SZ_B : g_size), DW_SRC, S_PACK2);
	end
end
S_PACK2: begin : pack2_state
	reg [31:0] bd;
	reg is_pack, is_unpk, is_cmpm;
	is_pack = (ir[15:12] == 4'h8) && (ir[8:6] == 3'b101);
	is_unpk = (ir[15:12] == 4'h8) && (ir[8:6] == 3'b110);
	is_cmpm = (ir[15:12] == 4'hB);
	bd = is_pack ? ((ir[11:9] == 3'd7) ? 32'd2 : 32'd1) : (is_unpk ? 32'd2 : size_bytes(g_size, ir[11:9] == 3'd7));
	if (is_cmpm) begin
		wreg({1'b1, ir[11:9]}, rf_b + bd);
		ea <= rf_b;
		rd(rf_b, g_size, DW_DST, S_PACK3);
	end else if (is_pack || is_unpk) begin
		// PACK/UNPK do not read the destination
		wreg({1'b1, ir[11:9]}, rf_b - bd);
		ea <= rf_b - bd;
		state <= S_PACK3;
	end else begin
		wreg({1'b1, ir[11:9]}, rf_b - bd);
		ea <= rf_b - bd;
		rd(rf_b - bd, g_size, DW_DST, S_PACK3);
	end
end
S_PACK3: begin : pack3_state
	reg is_pack, is_unpk, is_cmpm;
	reg [15:0] adj;
	reg [31:0] r;
	is_pack = (ir[15:12] == 4'h8) && (ir[8:6] == 3'b101);
	is_unpk = (ir[15:12] == 4'h8) && (ir[8:6] == 3'b110);
	is_cmpm = (ir[15:12] == 4'hB);
	adj = src[15:0] + ext;
	if (is_pack) begin
		r = {24'd0, adj[11:8], adj[3:0]};
		if (!ir[3]) begin wreg({1'b0, ir[11:9]}, {dst[31:8], r[7:0]}); finish; end
		else begin finish; wr(ea, `SZ_B, r, S_FETCH); end
	end else if (is_unpk) begin
		r = {16'd0, ({4'd0, src[7:4], 4'd0, src[3:0]} + ext)};
		if (!ir[3]) begin wreg({1'b0, ir[11:9]}, {dst[31:16], r[15:0]}); finish; end
		else begin finish; wr(ea, `SZ_W, r, S_FETCH); end
	end else begin
		sr[4:0] <= alu_f;
		if (is_cmpm) finish;
		else begin finish; wr(ea, g_size, alu_r, S_FETCH); end
	end
end

//-------------------------------------------------------------- TAS (read-modify-write, UM 7.3.3)
S_TAS: dreq(ea, `SZ_B, 1'b1, 32'd0, fc_data, 1'b1, 1'b0, DW_DST, S_TAS2);
S_TAS2: begin
	sr[4:0] <= alu_f;
	finish;
	dreq(ea, `SZ_B, 1'b0, alu_r, fc_data, 1'b1, 1'b1, DW_NONE, S_FETCH);
end

//-------------------------------------------------------------- MOVEP
S_MOVEP0: begin
	ea <= rf_a + sext16(ext);
	cnt <= 8'd0; tmp <= 32'd0; dst <= rf_b;
	state <= S_MOVEP1;
end
S_MOVEP1: begin : movep1
	reg [2:0] n;
	reg [7:0] wb;
	n = ir[6] ? 3'd4 : 3'd2;
	case ({ir[6] & ~cnt[1], ~cnt[0]})
		2'd3: wb = dst[31:24];
		2'd2: wb = dst[23:16];
		2'd1: wb = dst[15:8];
		default: wb = dst[7:0];
	endcase
	if (cnt[2:0] == n) begin
		if (!ir[7]) wreg({1'b0, ir[11:9]}, ir[6] ? tmp : {dst[31:16], tmp[15:0]});
		finish;
	end else if (ir[7]) begin
		cnt <= cnt + 8'd1;
		wr(ea + {cnt[6:0], 1'b0}, `SZ_B, {24'd0, wb}, S_MOVEP1);
	end else begin
		cnt <= cnt + 8'd1;
		rd(ea + {cnt[6:0], 1'b0}, `SZ_B, DW_TMP2, S_MOVEP2);
	end
end
S_MOVEP2: begin tmp <= {tmp[23:0], tmp2[7:0]}; state <= S_MOVEP1; end

//-------------------------------------------------------------- CHK (PRM)
S_CHK: begin : chk_state
	reg signed [31:0] v, b;
	reg [31:0] d;
	reg [3:0] nf;
	reg out_of;
	v = sext_sz(dst, g_size);
	b = sext_sz(src, g_size);
	d = b - v;
	out_of = (v < 0) || (v > b);
	// N, Z, V and C are undefined; the MC68020/030 values on both paths
	// (WinUAE setchkundefinedflags): V is the overflow of bound - Dn, C
	// follows the signs, both are clear when Dn is in bounds
	nf[3] = (v < 0);
	nf[2] = (v == 0);
	nf[1] = out_of && ((v[31] ^ b[31]) & ((g_size == `SZ_W ? d[15] : d[31]) ^ b[31]));
	nf[0] = out_of && ((v < 0) ? ((v > b) || (b >= 0)) : (b >= 0));
	sr[3:0] <= nf;
	if (out_of) begin
		exc_go(`VEC_CHK, `FMT_SIXWORD, scan_pc, pc_i);
		exc_sr <= {sr[15:4], nf};       // the frame holds the updated flags
	end else finish;
end
S_DIVZ: exc_go(`VEC_DIVZERO, `FMT_SIXWORD, scan_pc, pc_i);
// ---- end core/ap030_exec_a.vh ----
// ---- begin core/ap030_exec_b.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - states part B: exceptions, RTE, MOVEM, MUL/DIV, CHK2/CMP2,
// CAS/CAS2, bit fields

//-------------------------------------------------------------- exception processing (UM 8.1)
// a bus/address error waits here for the writes posted before it: their
// faults belong to earlier accesses (taken afterwards, not a double fault)
S_EXCW: begin
	exc_active <= 1'b0;
	if (!d_wpend) state <= S_EXC0;
end
S_EXC0: begin : exc0
	reg [31:0] base;
	reg use_msp;
	exc_active <= 1'b1;
	use_msp = exc_throw ? 1'b0 : sr_m;
	base = (use_msp ? msp_q : isp_q) - {frame_lw(exc_fmt), 2'b00};
	if (!exc_throw) begin
		// step 1: S set, tracing off, interrupt mask for interrupts
		sr[15:14] <= 2'b00;
		sr[13] <= 1'b1;
		if (exc_is_irq) sr[10:8] <= exc_ilvl;
		exc_cnt <= cnt; exc_dw_dst <= dw_dst; exc_dw_ret <= dw_ret;
	end
	exc_sp <= base;
	sp_we <= 1'b1; sp_sel <= use_msp ? 2'd2 : 2'd1; sp_wdata <= base;
	cnt <= 8'd0;
	state <= S_EXC1;
end
S_EXC1: begin
	// push the frame as longwords, ascending
	if (cnt[5:0] < frame_lw(exc_fmt)) begin
		cnt <= cnt + 8'd1;
		wr_sd(exc_sp + {cnt[5:0], 2'b00}, `SZ_L, frame_long_out(cnt[4:0]), S_EXC1);
	end else state <= S_EXC3;
end
S_EXC3: begin
	if (exc_is_irq && exc_sr[`SR_M] && !exc_throw) begin
		// UM 8.1.9: M set -- a throwaway frame goes on the interrupt stack
		exc_throw <= 1'b1;
		exc_fmt <= `FMT_THROWAWAY;
		sr[12] <= 1'b0;
		state <= S_EXC0;
	end else state <= S_EXC2;
end
S_EXC2: begin
	rd_sd(vbr + {22'd0, exc_vec, 2'b00}, `SZ_L, DW_TMP, S_EXC4);
	// system option: the level 7 autovector is always read from the bus, so
	// an external overlay of it (an Amiga freezer cartridge) is never missed
	if (nmi_vec_nocache && exc_vec == `VEC_AUTOVEC + 8'd7) d_nocache <= 1'b1;
end
S_EXC4: begin
	exc_active <= 1'b0; exc_is_irq <= 1'b0; exc_throw <= 1'b0; exc_busfault <= 1'b0;
	if (trace_after_exc) begin trace_pend <= 1'b1; trace_after_exc <= 1'b0; end
	// the trace that follows an instruction trap stacks the address of the
	// trapping instruction, the instruction that caused it (UM Table 8-6;
	// WinUAE trace_pc): pc_i keeps it until that trace
	if (!trace_after_exc) pc_i <= tmp;
	if (tmp[0]) begin
		// odd vector: address error (a double fault while processing a bus fault)
		if (exc_busfault) begin halted_r <= 1'b1; state <= S_HALT; end
		else begin
			exc_addr_err(tmp);
			// the frame's PC is the vector offset of the exception being
			// processed (WinUAE cputest doexcstack, 68020+; 68030 corpus v24)
			exc_pc <= {22'd0, exc_vec, 2'b00};
		end
	end else begin
		flush_req = 1'b1; flush_pc = tmp;
		state <= S_FETCH;
	end
end

//-------------------------------------------------------------- RTE (UM 8.1.13, 8.2.3)
// the frame is read in the current mode: after a throwaway frame whose SR
// has S clear, the next frame is on the user stack and read as user data
// (Hatari/WinUAE 68030 MMU; UNIX System V returns from signals this way)
S_RTE0: dreq(rf_c, `SZ_L, 1'b1, 32'd0, fc_data, 1'b0, 1'b0, DW_TMP, S_RTE1);
S_RTE1: dreq(rf_c + 32'd4, `SZ_L, 1'b1, 32'd0, fc_data, 1'b0, 1'b0, DW_TMP2, S_RTE2);
S_RTE2: begin
	case (tmp2[15:12])
		`FMT_NORMAL: begin
			sr <= tmp[31:16] & `SR_MASK;
			wreg(4'd15, rf_c + 32'd8);
			go_pc({tmp[15:0], tmp2[31:16]});
			// an odd PC faults after the SR is restored: the address error
			// frame holds the SR from the RTE frame (WinUAE 68030 AE corpus)
			if (tmp2[16]) exc_sr <= tmp[31:16] & `SR_MASK;
		end
		`FMT_THROWAWAY: begin
			// SR from the frame, then RTE again on the (possibly different) stack
			sr <= tmp[31:16] & `SR_MASK;
			wreg(4'd15, rf_c + 32'd8);
			state <= S_RTE0;
		end
		`FMT_SIXWORD: begin
			sr <= tmp[31:16] & `SR_MASK;
			wreg(4'd15, rf_c + 32'd12);
			go_pc({tmp[15:0], tmp2[31:16]});
			// an odd PC faults after the SR is restored: the address error
			// frame holds the SR from the RTE frame (WinUAE 68030 AE corpus)
			if (tmp2[16]) exc_sr <= tmp[31:16] & `SR_MASK;
		end
		`FMT_CPMID, `FMT_SHORTBUS, `FMT_LONGBUS: begin
			exc_sr <= tmp[31:16];
			exc_pc <= {tmp[15:0], tmp2[31:16]};
			exc_fmt <= tmp2[15:12];
			rte_ver_err <= 1'b0;
			cnt <= 8'd2;
			exc_busfault <= 1'b1;        // a fault while loading internal state halts (UM 8.1.13)
			state <= S_RTE3;
		end
		default: begin
			// the MC68030 clears T1/T0 before the format error: its frame
			// stacks SR without them (WinUAE gencpu, 68030 corpus)
			exc_pre(`VEC_FMTERR);
			exc_sr <= {2'b00, sr[13:0]};
			sr[15:14] <= 2'b00;
		end
	endcase
end
S_RTE3: begin
	if (cnt[5:0] < frame_lw(exc_fmt)) dreq(rf_c + {cnt[5:0], 2'b00}, `SZ_L, 1'b1, 32'd0, fc_data, 1'b0, 1'b0, DW_FRAME, S_RTE3);
	else state <= S_RTE4;
end
S_RTE4: begin : rte4
	exc_busfault <= 1'b0;
	if (exc_fmt == `FMT_LONGBUS && rte_ver_err) begin
		exc_pre(`VEC_FMTERR);            // version mismatch (UM 8.1.8)
		exc_sr <= {2'b00, sr[13:0]};     // T1/T0 cleared, as for any format error
		sr[15:14] <= 2'b00;
	end else begin
		sr <= exc_sr & `SR_MASK;
		wreg(4'd15, rf_c + {frame_lw(exc_fmt), 2'b00});
		if (exc_fmt == `FMT_CPMID) begin
			tr_t1 <= exc_sr[15]; tr_t0 <= exc_sr[14];
			exc_rk <= RK_BOUNDARY;
			flush_req = 1'b1; flush_pc = exc_pc;
			state <= S_CP1;
		end else if (exc_fmt == `FMT_SHORTBUS) begin
			if (exc_ssw[8]) begin
				// rerun the faulted data cycle, then continue at the PC
				dreq(exc_fa, sz_of_siz(exc_ssw[5:4]), exc_ssw[6], exc_dob, exc_ssw[2:0], exc_ssw[7], exc_ssw[7] & ~exc_ssw[6], DW_NONE, S_RTE_RERUN);
				tmp <= exc_pc;
			end else begin
				flush_req = 1'b1; flush_pc = exc_pc; state <= S_FETCH;
			end
		end else begin
			pc_i <= exc_pc;
			cnt <= exc_cnt;
			dw_dst <= exc_dw_dst;
			dw_ret <= exc_dw_ret;
			case (exc_rk)
				RK_RMW: begin
					// DF set: rerun the whole instruction; clear: it was emulated
					flush_req = 1'b1;
					flush_pc = exc_ssw[8] ? exc_pc : (exc_baddr - 32'd2);
					state <= S_FETCH;
				end
				RK_BOUNDARY: begin
					// a boundary fault resumes at the PC field, which the handler
					// may have changed (address error repair, UM 8.2.2)
					flush_req = 1'b1; flush_pc = exc_pc;
					state <= S_FETCH;
				end
				default: begin
					pipe_load = 1'b1; flush_pc = exc_baddr - 32'd2;
					pipe_c = exc_stage_c; pipe_c_v = ~exc_ssw[13];
					pipe_b = exc_stage_b; pipe_b_v = ~exc_ssw[12];
					if (exc_rk == RK_STREAM) state <= exc_rs;
					else if (exc_rk == RK_HELD) begin
						// rerun the posted write unless the handler completed it
						// (DF clear, UM 8.2.2), then issue the held access
						if (exc_ssw[8]) dreq(exc_fa, sz_of_siz(exc_ssw[5:4]), exc_ssw[6], exc_dob, exc_ssw[2:0], 1'b0, 1'b0, DW_NONE, S_RTE_HELD);
						else state <= S_RTE_HELD;
					end else if (exc_ssw[8]) begin
						// DF: rerun the data cycle described by the frame
						dreq(exc_fa, sz_of_siz(exc_ssw[5:4]), exc_ssw[6], exc_dob, exc_ssw[2:0], exc_ssw[7], exc_ssw[7] & ~exc_ssw[6], exc_dw_dst, exc_dw_ret);
						rerun_merge <= exc_ssw[6] && (exc_got != 3'd0);
					end else if (exc_rk == RK_READ) begin
						rte_fake <= 1'b1;
						d_size <= sz_of_siz(exc_ssw[5:4]);
						rerun_merge <= (exc_got != 3'd0);
						state <= S_DWAIT;
					end else state <= exc_dw_ret;
				end
			endcase
		end
	end
end
S_RTE_RERUN: begin flush_req = 1'b1; flush_pc = tmp; state <= S_FETCH; end
S_RTE_HELD: begin
	// the access the instruction was suspended at, then its continuation;
	// an access that ended the instruction had its trace decided already
	dreq(exc_partial, exc_held[10:9], exc_held[8], exc_dib, exc_held[7:5], exc_held[4], exc_held[3], exc_dw_dst, exc_dw_ret);
	d_nocache <= exc_held[2];
	cpu_flt_ill <= exc_held[1]; cpu_flt_fline <= exc_held[0];
	if (exc_dw_ret == S_FETCH) trace_pend <= tr_t1 | (tr_t0 & flow);
end

//-------------------------------------------------------------- MOVEM (PRM)
S_MOVEM0: begin : movem0
	reg [15:0] m;
	reg desc;
	desc = (ir[5:3] == 3'b100);
	// -(An): mask bit 0 is A7; descending addresses
	m = desc ? {ext[0], ext[1], ext[2], ext[3], ext[4], ext[5], ext[6], ext[7],
	            ext[8], ext[9], ext[10], ext[11], ext[12], ext[13], ext[14], ext[15]} : ext;
	mm_mask <= m;
	cnt <= {4'd0, mm_next(m, desc)};
	if (desc) begin ea <= rf_a; tmp2 <= rf_a; end
	else if (ir[5:3] == 3'b011) ea <= rf_a;
	state <= S_MOVEM1;
end
S_MOVEM1: begin : movem1
	reg [3:0] r;
	reg [15:0] next_mask;
	reg desc;
	reg [31:0] bytes, v;
	desc = (ir[5:3] == 3'b100);
	bytes = ir[6] ? 32'd4 : 32'd2;
	r = cnt[3:0];
	next_mask = mm_mask & ~(16'd1 << r);
	if (mm_mask == 16'd0) begin
		if (ir[5:3] == 3'b011 || desc) wreg({1'b1, ir[2:0]}, ea);
		finish_dispatch;
	end else begin
		mm_mask <= next_mask;
		cnt <= {4'd0, mm_next(next_mask, desc)};
		if (ir[10]) begin
			// memory to registers
			dw_reg <= r;
			ea <= ea + bytes;
			rd(ea, ir[6] ? `SZ_L : `SZ_W, DW_REGL, S_MOVEM1);
		end else begin
			// registers to memory: the value read through port A (cnt) this clock;
			// the predecrement base register stores its initial value minus the size
			v = (desc && r == {1'b1, ir[2:0]}) ? (tmp2 - bytes) : rf_a;
			ea <= desc ? (ea - bytes) : (ea + bytes);
			wr(desc ? (ea - bytes) : ea, ir[6] ? `SZ_L : `SZ_W, v, S_MOVEM1);
		end
	end
end

//-------------------------------------------------------------- MUL / DIV
S_MULDIV0: begin : muldiv0
	reg long;
	reg is_div;
	reg sgn;
	long = (ir[15:12] == 4'h4);
	is_div = long ? ir[6] : (ir[15:12] == 4'h8);
	sgn = long ? ext[11] : ir[8];
	if (is_div && ((long ? src : {16'd0, src[15:0]}) == 32'd0)) begin
		state <= S_DIVZ;                    // UM 8.1.4: divide by zero
		// the flags are undefined; the MC68020/030 values (WinUAE
		// divbyzero_special, divsl_divbyzero, divul_divbyzero)
		if (!long) begin
			if (sgn) sr[3:0] <= 4'b0100;
			else sr[3:0] <= {dst[31], dst[31:16] == 16'd0, 1'b1, 1'b0};
		end else if (sgn) begin
			sr[3] <= 1'b0; sr[2] <= 1'b1; sr[0] <= 1'b0;     // V is not changed
		end else
			sr[3:0] <= {rf_a[31], rf_a == 32'd0, 1'b1, 1'b0};
	end else begin
		md_start <= 1'b1;
		md_div <= is_div;
		md_sign <= sgn;
		if (!long) tm_md <= is_div ? (sgn ? 2'd3 : 2'd2) : 2'd1;
		if (long) begin
			md_a <= src;
			md_lo <= rf_a;                            // Dq
			md_hi <= ext[10] ? rf_b : (sgn ? {32{rf_a[31]}} : 32'd0);   // Dr:Dq for the 64-bit form
			tmp <= rf_a; tmp2 <= rf_b;
		end else begin
			md_a <= sgn ? sext16(src[15:0]) : {16'd0, src[15:0]};
			md_lo <= is_div ? dst : (sgn ? sext16(dst[15:0]) : {16'd0, dst[15:0]});
			md_hi <= (is_div && sgn) ? {32{dst[31]}} : 32'd0;
		end
		state <= S_MULDIV1;
	end
end
S_MULDIV1: if (md_done) begin : muldiv1
	reg long, is_div, sgn;
	reg [31:0] aquot;
	reg abs_ovf;
	aquot = md_rlo[31] ? (32'd0 - md_rlo) : md_rlo;
	abs_ovf = md_ovf || (aquot[31:16] != 16'd0);
	long = (ir[15:12] == 4'h4);
	is_div = long ? ir[6] : (ir[15:12] == 4'h8);
	sgn = long ? ext[11] : ir[8];
	if (!long) begin
		if (is_div) begin
			// word divide: 16-bit quotient range check
			if (md_ovf || (sgn ? (md_rlo[31:16] != {16{md_rlo[15]}}) : (md_rlo[31:16] != 16'd0))) begin
				// overflow: V set, the rest undefined; the MC68020/030 values
				// (WinUAE setdivuflags/setdivsflags)
				if (!sgn) begin
					sr[1] <= 1'b1;                       // Z and C are not changed
					if (dst[31]) sr[3] <= 1'b1;          // N set by a negative dividend
				end else begin
					// N and Z from the low byte of |quotient| unless the quotient
					// does not fit in 16 bits at all
					sr[1] <= 1'b1; sr[0] <= 1'b0;
					sr[3] <= !abs_ovf && aquot[7];
					sr[2] <= !abs_ovf && (aquot[7:0] == 8'd0);
				end
			end else begin
				wreg({1'b0, ir[11:9]}, {md_rhi[15:0], md_rlo[15:0]});
				sr[3] <= md_rlo[15]; sr[2] <= (md_rlo[15:0] == 16'd0); sr[1] <= 1'b0; sr[0] <= 1'b0;
			end
		end else begin
			wreg({1'b0, ir[11:9]}, md_rlo);
			sr[3] <= md_rlo[31]; sr[2] <= (md_rlo == 32'd0); sr[1] <= 1'b0; sr[0] <= 1'b0;
		end
		finish;
	end else if (is_div) begin
		if (md_ovf) begin
			// overflow: V set, C clear, N and Z undefined; the MC68020/030
			// values (WinUAE divul_overflow/divsl_overflow) from the dividend
			sr[1] <= 1'b1; sr[0] <= 1'b0;
			if (!sgn) begin
				sr[3] <= tmp[31]; sr[2] <= (tmp == 32'd0);
			end else if (ext[10] && tmp2 == 32'd0) begin
				sr[3] <= 1'b0; sr[2] <= 1'b1;
			end else if (ext[10] && tmp2[31] && src[31] && ($signed(tmp2) > $signed(src))) begin
				sr[3] <= 1'b0; sr[2] <= 1'b0;
			end else if (tmp == 32'd0) begin
				sr[3] <= 1'b0; sr[2] <= 1'b1;
			end else begin
				sr[3] <= tmp[31] ^ (ext[10] & tmp2[31]); sr[2] <= 1'b0;
			end
			finish;
		end else begin
			wreg({1'b0, ext[14:12]}, md_rlo);       // Dq = quotient
			sr[3] <= md_rlo[31]; sr[2] <= (md_rlo == 32'd0); sr[1] <= 1'b0; sr[0] <= 1'b0;
			if (ext[2:0] != ext[14:12]) state <= S_MULDIV2;   // Dr = remainder
			else finish;
		end
	end else begin
		wreg({1'b0, ext[14:12]}, md_rlo);           // Dq = low product
		if (ext[10]) begin
			sr[3] <= md_rhi[31]; sr[2] <= (md_rhi == 32'd0) && (md_rlo == 32'd0); sr[1] <= 1'b0; sr[0] <= 1'b0;
			state <= S_MULDIV2;                     // Dr = high product
		end else begin
			sr[3] <= md_rlo[31]; sr[2] <= (md_rlo == 32'd0); sr[0] <= 1'b0;
			sr[1] <= sgn ? (md_rhi != {32{md_rlo[31]}}) : (md_rhi != 32'd0);
			finish;
		end
	end
end
S_MULDIV2: begin wreg({1'b0, ext[2:0]}, md_rhi); finish; end

//-------------------------------------------------------------- CHK2 / CMP2 (PRM)
S_CHK2_1: rd(ea + {29'd0, bytes_of_sz(g_size)}, g_size, DW_DST, S_CHK2_2);
S_CHK2_2: begin : chk2
	reg [31:0] lo, hi, rn;
	reg [3:0] nf;
	if (ext[15]) begin lo = sext_sz(src, g_size); hi = sext_sz(dst, g_size); rn = rf_a; end
	else begin
		case (g_size)
			`SZ_B: begin lo = {24'd0, src[7:0]}; hi = {24'd0, dst[7:0]}; rn = {24'd0, rf_a[7:0]}; end
			`SZ_W: begin lo = {16'd0, src[15:0]}; hi = {16'd0, dst[15:0]}; rn = {16'd0, rf_a[15:0]}; end
			default: begin lo = src; hi = dst; rn = rf_a; end
		endcase
	end
	nf[2] = (rn == lo) || (rn == hi);
	nf[0] = (lo <= hi) ? ((rn < lo) || (rn > hi)) : ((rn > hi) && (rn < lo));
	{nf[3], nf[1]} = chk2_nv(ext[15] ? lo : sext_sz(lo, g_size), ext[15] ? hi : sext_sz(hi, g_size),
	                         ext[15] ? rn : sext_sz(rn, g_size));
	sr[3:0] <= nf;
	if (ext[11] && nf[0]) begin
		exc_go(`VEC_CHK, `FMT_SIXWORD, scan_pc, pc_i);
		exc_sr <= {sr[15:4], nf};       // the frame holds the updated flags
	end else finish;
end

//-------------------------------------------------------------- CAS / CAS2 (UM 7.3.3)
S_CAS0: dreq(ea, g_size, 1'b1, 32'd0, fc_data, 1'b1, 1'b0, DW_DST, S_CAS1);
S_CAS1: begin
	// the compare: its flags are registered, the decision follows a clock
	// later (the register file, the ALU and the decision in one clock is
	// the longest path of the core)
	sr[4:0] <= alu_f;
	state <= S_CAS1B;
end
S_CAS1B: begin
	if (sr[2]) begin
		finish;
		dreq(ea, g_size, 1'b0, rf_b, fc_data, 1'b1, 1'b1, DW_NONE, S_FETCH);
	end else begin
		wreg({1'b0, ext[2:0]}, merge(rf_a, dst, g_size));
		d_rmc_release <= 1'b1;
		finish;
	end
end
S_CAS2_0: begin
	if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
	else begin tmp3 <= {1'b0, w0}; pop(2'd1); state <= S_CAS2_1; end
end

S_CAS2_1: begin ea <= rf_c; tmp3[16] <= 1'b1; state <= S_CAS2_2; end
S_CAS2_2: begin ea2 <= rf_c; tmp3[16] <= 1'b0; dreq(ea, g_size, 1'b1, 32'd0, fc_data, 1'b1, 1'b0, DW_SRC, S_CAS2_3); end
S_CAS2_3: dreq(ea2, g_size, 1'b1, 32'd0, fc_data, 1'b1, 1'b0, DW_DST, S_CAS2_4);
S_CAS2_4: begin
	// operand 1 against Dc1 (flags registered, decision next clock)
	sr[4:0] <= alu_f;
	tmp <= rf_b;                                  // Du1
	state <= S_CAS2_4B;
end
S_CAS2_4B: begin
	if (sr[2]) begin tmp3[16] <= 1'b1; state <= S_CAS2_5; end
	else begin
		wreg({1'b0, ext[2:0]}, merge(rf_a, src, g_size));
		tmp3[16] <= 1'b1; state <= S_CAS2_6;
	end
end
S_CAS2_5: begin
	// operand 2 against Dc2
	sr[4:0] <= alu_f;
	tmp2 <= rf_b;                                 // Du2
	state <= S_CAS2_5B;
end
S_CAS2_5B: begin
	// both equal: operand 2 is written first, then operand 1 (the MC68030
	// order as modelled by WinUAE; visible when the operands overlap)
	if (sr[2]) dreq(ea2, g_size, 1'b0, tmp2, fc_data, 1'b1, 1'b0, DW_NONE, S_CAS2_7);
	else begin
		wreg({1'b0, tmp3[2:0]}, merge(rf_a, dst, g_size));
		tmp3[16] <= 1'b0; state <= S_CAS2_8;
	end
end
// a mismatch loads Dc2 and then Dc1: when both name one register, it
// receives operand 1 (Dc1 was written in S_CAS2_4B and is kept)
S_CAS2_6: begin
	if (tmp3[2:0] != ext[2:0]) wreg({1'b0, tmp3[2:0]}, merge(rf_a, dst, g_size));
	d_rmc_release <= 1'b1; finish;
end
S_CAS2_7: begin finish; dreq(ea, g_size, 1'b0, tmp, fc_data, 1'b1, 1'b1, DW_NONE, S_FETCH); end
S_CAS2_8: begin wreg({1'b0, ext[2:0]}, merge(rf_a, src, g_size)); d_rmc_release <= 1'b1; finish; end

//-------------------------------------------------------------- bit fields (PRM)
S_BF0: begin : bf0
	reg [5:0] w;
	w = ext[5] ? ((rf_c[4:0] == 5'd0) ? 6'd32 : {1'b0, rf_c[4:0]}) : ((ext[4:0] == 5'd0) ? 6'd32 : {1'b0, ext[4:0]});
	tmp <= ext[11] ? rf_b : {27'd0, ext[10:6]};   // offset (signed when from a register)
	cnt <= {2'd0, w};
	tmp2 <= rf_a;                                  // Dn (BFINS source)
	state <= S_BF1;
end
S_BF1: begin : bf1
	reg [31:0] base;
	reg [6:0] total;
	reg [2:0] nb;
	if (ir[5:3] == 3'b000) begin
		dst <= rotl32(rf_b, tmp[4:0]);             // pre-rotate data register operand to MSB
		state <= S_BF3;
	end else begin
		base = ea + {{3{tmp[31]}}, tmp[31:3]};
		total = {4'd0, tmp[2:0]} + {1'b0, cnt[5:0]};
		nb = total[5:3] + {2'd0, (total[2:0] != 3'd0)};
		ea <= base;
		sub <= {5'd0, nb};
		rd(base, (nb >= 3'd4) ? `SZ_L : sz_of_bytes(nb), DW_DST, (nb == 3'd5) ? S_BF2 : S_BF3);
	end
end
// the fifth byte goes to src: tmp2 holds the BFINS source register
S_BF2: rd(ea + 32'd4, `SZ_B, DW_SRC, S_BF3);
S_BF3: begin : bf3
	reg [39:0] d40, sh40, n40;
	reg [31:0] msb_fld, fld, ins_msb, tmask, rot2;
	reg [5:0] w;
	reg [2:0] nb;
	reg n, z;
	w = cnt[5:0];
	nb = sub[2:0];
	d40 = (nb == 3'd5) ? {dst, src[7:0]} : ({dst, 8'd0} << (8 * (3'd4 - nb)));
	sh40 = d40 << tmp[2:0];
	msb_fld = (ir[5:3] == 3'b000) ? dst : sh40[39:8];
	fld = (w >= 6'd32) ? msb_fld : (msb_fld >> (6'd32 - w));
	tmask = topmask(w);
	ins_msb = ((w >= 6'd32) ? tmp2 : (tmp2 << (6'd32 - w))) & tmask;
	n = (ir[10:8] == 3'b111) ? ins_msb[31] : msb_fld[31];
	z = (ir[10:8] == 3'b111) ? (ins_msb == 32'd0) : (fld == 32'd0);
	sr[3] <= n; sr[2] <= z; sr[1] <= 1'b0; sr[0] <= 1'b0;
	case (ir[10:8])
		3'b001: begin wreg({1'b0, ext[14:12]}, fld); finish; end                                   // BFEXTU
		3'b011: begin wreg({1'b0, ext[14:12]}, (w >= 6'd32) ? fld : (msb_fld[31] ? (fld | (32'hFFFFFFFF << w)) : fld)); finish; end   // BFEXTS
		3'b101: begin wreg({1'b0, ext[14:12]}, tmp + {26'd0, field_lz_msb(msb_fld, w)}); finish; end // BFFFO
		3'b000: finish;                                                                           // BFTST
		default: begin
			// BFCHG / BFCLR / BFSET / BFINS write back
			case (ir[10:8])
				3'b010: rot2 = msb_fld ^ tmask;
				3'b100: rot2 = msb_fld & ~tmask;
				3'b110: rot2 = msb_fld | tmask;
				default: rot2 = (msb_fld & ~tmask) | ins_msb;
			endcase
			if (ir[5:3] == 3'b000) begin
				wreg({1'b0, ir[2:0]}, rotr32(rot2, tmp[4:0]));
				finish;
			end else begin
				n40 = (d40 & ~(40'hFF_FFFF_FFFF >> tmp[2:0])) | ({rot2, sh40[7:0]} >> tmp[2:0]);
				tmp3 <= {9'd0, n40[7:0]};
				if (nb == 3'd5) wr(ea, `SZ_L, n40[39:8], S_BFWR);
				else begin finish; wr(ea, sz_of_bytes(nb), n40[39:8] >> (8 * (3'd4 - nb)), S_FETCH); end
			end
		end
	endcase
end
S_BFWR: begin finish; wr(ea + 32'd4, `SZ_B, {15'd0, tmp3}, S_FETCH); end

// ---- end core/ap030_exec_b.vh ----
// ---- begin core/ap030_exec_c.vh (inlined by tools/import_falcon.py) ----
// AP68030 core - states part C: coprocessor interface (UM Section 10) and
// MMU instructions (UM 9.8)
//
// cp_kind: 0 cpGEN, 1 cpBcc, 2 cpDBcc, 3 cpScc, 4 cpTRAPcc
// cp_base: CIR set base (CPU space type 2, CpID on A13-A15)

//-------------------------------------------------------------- instruction start
S_CP0: begin
	// cpGEN: the command word to the command CIR ($0A)
	cp_id <= ir[11:9];
	cp_kind <= 4'd0; cp_cond <= 1'b0; cp_pcbit <= 1'b0; cp_trace_wait <= 1'b0;
	cpu_flt_fline <= 1'b1;
	dreq({14'd0, 1'b1, 1'b0, ir[11:9], 13'd0} | 32'h0A, `SZ_W, 1'b0, {16'd0, ext}, `FC_CPU_SPACE, 1'b0, 1'b0, DW_NONE, S_CP1);
end
S_CPBCC: begin
	// cpBcc: the operation word to the condition CIR ($0E)
	cp_id <= ir[11:9];
	cp_kind <= 4'd1; cp_cond <= 1'b1; cp_pcbit <= 1'b0; cp_trace_wait <= 1'b0;
	cpu_flt_fline <= 1'b1;
	dreq({14'd0, 1'b1, 1'b0, ir[11:9], 13'd0} | 32'h0E, `SZ_W, 1'b0, {16'd0, ir}, `FC_CPU_SPACE, 1'b0, 1'b0, DW_NONE, S_CP1);
end
S_CPDBCC, S_CPSCC, S_CPTRAP: begin
	// the condition selector word (second word) to the condition CIR
	cp_id <= ir[11:9];
	cp_kind <= (state == S_CPDBCC) ? 4'd2 : (state == S_CPSCC) ? 4'd3 : 4'd4;
	cp_cond <= 1'b1; cp_pcbit <= 1'b0; cp_trace_wait <= 1'b0;
	cpu_flt_fline <= 1'b1;
	dreq({14'd0, 1'b1, 1'b0, ir[11:9], 13'd0} | 32'h0E, `SZ_W, 1'b0, {16'd0, ext}, `FC_CPU_SPACE, 1'b0, 1'b0, DW_NONE, S_CP1);
end

//-------------------------------------------------------------- response dialogue
S_CP1: begin
	cpu_flt_fline <= 1'b0;
	cir_rd(5'h00, `SZ_W, DW_TMP, S_CP2);
end
S_CP2: begin : cp2
	reg [15:0] r;
	r = tmp[15:0];
	cp_resp <= r;
	cp_ca <= r[15]; cp_dr <= r[13];
	if (r[14] && !cp_pcbit) begin
		// PC bit: the instruction address to the instruction address CIR first
		cp_pcbit <= 1'b1;
		cir_wr(5'h18, `SZ_L, pc_i, S_CP2);
	end else begin
		cp_pcbit <= 1'b0;
		casez (r[12:8])
			5'b00000: begin
				// write to previously evaluated EA (DR=1; bits 13:8 = $00 are
				// undefined, UM 10.6)
				if (cp_cond || !r[13]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else begin cp_len <= r[7:0]; cp_pos <= 8'd0; cp_dr <= 1'b1; state <= S_CPXFER; end
			end
			5'b00001: begin
				// transfer multiple coprocessor registers
				if (cp_cond || r[0]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else if (!(r[13] ? (ir_ea_ctrlalt || ir_ea_pd) : (ir_ea_ctrl || ir_ea_pi))) begin
					tmp <= {24'd0, `VEC_FLINE}; cir_wr(5'h02, `SZ_W, 32'h0001, S_CP_ABORT);
				end else begin cp_len <= r[7:0]; state <= S_CPMULT; end
			end
			5'b00100: begin
				if (r[13]) begin
					// busy: service interrupts with a pre-instruction frame, restart
					if (irq_pend) begin iack_pc_i <= 1'b1; exc_ilvl <= irq_lvl; state <= S_IACK; end
					else begin flush_req = 1'b1; flush_pc = pc_i; state <= S_FETCH; end
				end else begin
					// supervisor check
					if (cp_cond && !r[15]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
					else if (!sr_s) begin tmp <= {24'd0, `VEC_PRIV}; cir_wr(5'h02, `SZ_W, 32'h0001, S_CP_ABORT); end
					else state <= S_CP1;
				end
			end
			5'b00101: begin
				// take address and transfer data: the address goes to tmp2, ea
				// keeps the evaluated EA for a write to previously evaluated EA
				// and the mid-instruction frame (UM 10.4.10)
				if (cp_cond && !r[15]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else begin cp_len <= r[7:0]; cp_pos <= 8'd0; cir_rd(5'h1C, `SZ_L, DW_TMP2, S_CPXFER); end
			end
			5'b00110: begin
				// transfer multiple main processor registers
				if (cp_cond && !r[15]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else cir_rd(5'h14, `SZ_W, DW_TMP, S_CPREGS);
			end
			5'b00111: begin
				// transfer operation word
				if (cp_cond && !r[15]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else cir_wr(5'h08, `SZ_W, {16'd0, ir}, S_CPWAIT);
			end
			5'b0100?: begin
				// null (DR=0; $28/$29 are undefined, UM 10.6)
				if (r[13]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else state <= S_CPNULL;
			end
			5'b01010: begin
				// evaluate and transfer effective address (DR=0; $2A is undefined, UM 10.6)
				if (cp_cond || r[13]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else if (!ir_ea_ctrlalt) begin tmp <= {24'd0, `VEC_FLINE}; cir_wr(5'h02, `SZ_W, 32'h0001, S_CP_ABORT); end
				else begin ea_ret <= S_CPEAX; state <= S_EA; end
			end
			5'b01100: begin
				// transfer single main processor register (D/A in bit 3, number in 2:0)
				if (cp_cond && !r[15]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else state <= S_CPREG;
			end
			5'b01101: begin
				// transfer main processor control register
				if (cp_cond && !r[15]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else cir_rd(5'h14, `SZ_W, DW_TMP, S_CPCTRL);
			end
			5'b01110: begin
				// transfer to/from top of stack
				if ((cp_cond && !r[15]) || !(r[7:0] == 8'd1 || r[7:0] == 8'd2 || r[7:0] == 8'd4))
					exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else begin cp_len <= r[7:0]; state <= S_CPTOS; end
			end
			5'b01111: begin
				// transfer from instruction stream
				if ((cp_cond && !r[15]) || r[0]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else begin cp_len <= r[7:0]; cp_pos <= 8'd0; state <= S_CP_ISTREAM; end
			end
			5'b0001?: begin
				// transfer status register and scanPC
				if (cp_cond) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else state <= S_CPSR;
			end
			5'b10???: begin
				// evaluate effective address and transfer data: an EA outside
				// the primitive's category is an F-line (abort); a write to a
				// non-alterable EA, a register length other than 1, 2 or 4 and
				// an odd immediate length above 1 are protocol violations even
				// when the category matches (UM 10.4.9, Table 10-6)
				if (cp_cond) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else if (!cp_ea_ok(r[10:8])) begin
					tmp <= {24'd0, `VEC_FLINE}; cir_wr(5'h02, `SZ_W, 32'h0001, S_CP_ABORT);
				end else if ((r[13] && !ir_ea_alt) ||
				             ((ir_ea_dn || ir_ea_an) && !(r[7:0] == 8'd1 || r[7:0] == 8'd2 || r[7:0] == 8'd4)) ||
				             (ir_ea_imm && r[0] && r[7:0] != 8'd1))
					exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
				else begin cp_len <= r[7:0]; cp_pos <= 8'd0; state <= S_CPXEA; end
			end
			5'b11100: begin tmp <= {24'd0, r[7:0]}; cp_kind[3] <= 1'b0; cir_wr(5'h02, `SZ_W, 32'h0002, S_CP_EXC); sub <= 8'd0; end
			5'b11101: begin tmp <= {24'd0, r[7:0]}; cir_wr(5'h02, `SZ_W, 32'h0002, S_CP_EXC); sub <= 8'd1; end
			5'b11110: begin tmp <= {24'd0, r[7:0]}; cir_wr(5'h02, `SZ_W, 32'h0002, S_CP_EXC); sub <= 8'd2; end
			default: exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
		endcase
	end
end
// after a service: come again, or the instruction is done
S_CPWAIT: begin
	if (cp_ca) state <= S_CP1;
	else if (cp_cond) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);   // conditional needs a null to finish
	// a pending trace: the dialog goes on until null CA=0 PF=1 or a take
	// post-instruction exception (UM 10.5.2.5)
	else if (tr_t1 || cp_trace_wait) state <= S_CP1;
	else finish;
end
S_CP_ABORT: begin
	// the instruction was aborted with $0001 in the control CIR; the caller
	// left the vector (F-line, privilege violation or format error) in tmp
	exc_pre(tmp[7:0]);
end
S_CP_EXC: begin
	// take pre/mid/post-instruction exception (acknowledged with $0002)
	case (sub[1:0])
		2'd0: exc_go(tmp[7:0], `FMT_NORMAL, pc_i, 32'd0);
		2'd1: exc_go(tmp[7:0], `FMT_CPMID, scan_pc, pc_i);
		default: exc_go(tmp[7:0], `FMT_SIXWORD, scan_pc, pc_i);
	endcase
end
S_CPNULL: begin
	// null primitive (UM Table 10-3)
	if (cp_resp[15]) begin
		// come again; IA allows interrupts, serviced with a mid-instruction frame
		if (cp_resp[8] && irq_pend) begin iack_cpmid <= 1'b1; exc_ilvl <= irq_lvl; state <= S_IACK; end
		else state <= S_CP1;
	end else if (cp_cond) begin
		// TF completes the conditional instruction
		case (cp_kind)
			4'd1: state <= S_CPBCC2;
			4'd2: state <= S_CPDBCC2;
			4'd3: state <= S_CPSCC2;
			default: state <= S_CPTRAP2;
		endcase
	end else if ((tr_t1 || cp_trace_wait) && !cp_resp[1]) begin
		// a pending trace waits for processing finished (UM 10.5.2.5)
		if (cp_resp[8] && irq_pend) begin iack_cpmid <= 1'b1; exc_ilvl <= irq_lvl; state <= S_IACK; end
		else state <= S_CP1;
	end else begin
		finish;
		// trace on change of flow: a transfer of SR and scanPC into the
		// processor made the trace pending (UM 10.4.17, 10.5.2.5)
		if (cp_trace_wait) trace_pend <= 1'b1;
	end
end

//-------------------------------------------------------------- conditional completions
S_CPBCC2: begin : cpbcc2
	reg two, ok, flt;
	reg [31:0] target;
	two = ir[6];
	ok = pipe_ready(two); flt = pipe_faulted(two);
	target = two ? (scan_pc + {w0, w1}) : (scan_pc + sext16(w0));
	if (!ok) ; else if (flt) exc_stream_fault(two, 1'b0);
	else begin
		pop(two ? 2'd2 : 2'd1);
		if (cp_resp[0]) go_pc(target); else finish;
	end
end
S_CPDBCC2: begin : cpdbcc2
	reg [15:0] nw;
	nw = rf_a[15:0] - 16'd1;
	if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
	else if (cp_resp[0]) begin pop(2'd1); finish; end
	else begin
		wreg({1'b0, ir[2:0]}, {rf_a[31:16], nw});
		pop(2'd1);
		if (nw != 16'hFFFF) go_pc(scan_pc + sext16(w0));
		else finish;
	end
end
S_CPSCC2: begin
	// Dn: only its low byte changes (UM 10.2.2.2); the upper bytes are read
	// now, not taken from dst: the dialog may have loaded Dn (transfer main
	// processor register), and after a mid-instruction frame's RTE dst
	// holds whatever the handler left there
	if (ir[5:3] == 3'b000) begin wreg({1'b0, ir[2:0]}, {rf_a[31:8], {8{cp_resp[0]}}}); finish; end
	else begin ea_ret <= S_CPSCC_WR; state <= S_EA; end
end
S_CPSCC_WR: begin finish; wr(ea, `SZ_B, {24'd0, {8{cp_resp[0]}}}, S_FETCH); end   // cpScc memory destination
S_CPTRAP2: begin : cptrapcc
	// cpTRAPcc completion: skip the operand words, trap when true
	reg [1:0] npop;
	reg ok, flt, two;
	if (ir[2:0] == 3'b010) begin npop = 2'd1; ok = w0_v; flt = w0_v & w0_f; two = 1'b0; end
	else if (ir[2:0] == 3'b011) begin npop = 2'd2; ok = have2; flt = pipe_faulted(1'b1); two = 1'b1; end
	else begin npop = 2'd0; ok = 1'b1; flt = 1'b0; two = 1'b0; end
	if (!ok) ; else if (flt) exc_stream_fault(two, 1'b0);
	else begin
		pop(npop);
		if (cp_resp[0]) exc_go(`VEC_TRAPCC, `FMT_SIXWORD, scan_pc + {29'd0, npop, 1'b0}, pc_i);
		else finish;
	end
end

//-------------------------------------------------------------- primitives with transfers
S_CPEAX: cir_wr(5'h1C, `SZ_L, ea, S_CPWAIT);                    // evaluate and transfer EA
S_CP_ISTREAM: begin : cpistream
	// operand words from the instruction stream to the operand CIR
	reg [7:0] rem;
	rem = cp_len - cp_pos;
	if (rem == 8'd0) state <= S_CPWAIT;
	else if (rem >= 8'd4) begin
		if (!have2) ; else if (pipe_faulted(1'b1)) exc_stream_fault(1'b1, 1'b0);
		else begin pop(2'd2); cp_pos <= cp_pos + 8'd4; cir_wr(5'h10, `SZ_L, {w0, w1}, S_CP_ISTREAM); end
	end else begin
		if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
		else begin pop(2'd1); cp_pos <= cp_pos + 8'd2; cir_wr(5'h10, `SZ_W, {16'd0, w0}, S_CP_ISTREAM); end
	end
end
S_CPXEA: begin : cpxea
	// evaluate EA and transfer data: register direct, immediate, or memory
	reg [31:0] bytes;
	bytes = {24'd0, cp_len};
	if (ir_ea_dn || ir_ea_an) begin
		dw_reg <= {ir_ea_an, ir[2:0]};
		if (!cp_dr) cir_wr(5'h10, sz_of_bytes(cp_len[2:0]), ir_ea_an ? rf_b : rf_c, S_CPWAIT);
		else begin dst <= ir_ea_an ? rf_b : rf_c; cir_rd(5'h10, sz_of_bytes(cp_len[2:0]), ir_ea_an ? DW_REGL : DW_REG, S_CPWAIT); end
	end else if (ir_ea_imm) begin
		// immediate: from the instruction stream (byte operands take a word)
		cp_pos <= 8'd0;
		if (cp_len == 8'd1) begin
			if (!w0_v) ; else if (w0_f) exc_stream_fault(1'b0, 1'b0);
			else begin pop(2'd1); cir_wr(5'h10, `SZ_B, {24'd0, w0[7:0]}, S_CPWAIT); end
		end else state <= S_CP_ISTREAM;
	end else if (ir_ea_pi) begin
		ea <= rf_b;
		wreg({1'b1, ir[2:0]}, rf_b + ((cp_len == 8'd1 && ir[2:0] == 3'd7) ? 32'd2 : bytes));
		state <= S_CPXFER;
	end else if (ir_ea_pd) begin
		ea <= rf_b - ((cp_len == 8'd1 && ir[2:0] == 3'd7) ? 32'd2 : bytes);
		wreg({1'b1, ir[2:0]}, rf_b - ((cp_len == 8'd1 && ir[2:0] == 3'd7) ? 32'd2 : bytes));
		state <= S_CPXFER;
	end else begin
		ea_ret <= S_CPXFER; state <= S_EA;
	end
end
S_CPXFER: begin : cpxfer
	// memory <-> operand CIR in longword parts, ascending (UM 10.3.8).  The
	// take address and transfer data primitive's address is in tmp2 and its
	// operand in data space (UM 10.4.11); the evaluated EA's reads are
	// program references when the EA is PC-relative
	reg [7:0] rem;
	reg [2:0] chunk;
	rem = cp_len - cp_pos;
	chunk = (rem >= 8'd4) ? 3'd4 : rem[2:0];
	if (rem == 8'd0) state <= S_CPWAIT;
	else if (cp_dr) cir_rd(5'h10, sz_of_bytes(chunk), DW_TMP, S_CPXFER3);
	else if (cp_resp[12:8] == 5'b00101)
		dreq(tmp2 + {24'd0, cp_pos}, sz_of_bytes(chunk), 1'b1, 32'd0, fc_data, 1'b0, 1'b0, DW_TMP, S_CPXFER2);
	else rd(ea + {24'd0, cp_pos}, sz_of_bytes(chunk), DW_TMP, S_CPXFER2);
end
S_CPXFER2: begin : cpxfer2
	reg [7:0] rem; reg [2:0] chunk;
	rem = cp_len - cp_pos; chunk = (rem >= 8'd4) ? 3'd4 : rem[2:0];
	cp_pos <= cp_pos + {5'd0, chunk};
	cir_wr(5'h10, sz_of_bytes(chunk), tmp, S_CPXFER);
end
S_CPXFER3: begin : cpxfer3
	reg [7:0] rem; reg [2:0] chunk;
	rem = cp_len - cp_pos; chunk = (rem >= 8'd4) ? 3'd4 : rem[2:0];
	cp_pos <= cp_pos + {5'd0, chunk};
	wr(((cp_resp[12:8] == 5'b00101) ? tmp2 : ea) + {24'd0, cp_pos}, sz_of_bytes(chunk), tmp, S_CPXFER);
end
S_CPTOS: begin
	// transfer to/from top of stack: (A7)+ to the coprocessor, or -(A7) from
	// it (UM 10.4.12), in data space; the -(A7) address goes to tmp2, ea
	// keeps the evaluated EA (UM 10.4.10)
	if (!cp_dr) begin
		wreg(4'd15, rf_c + ((cp_len == 8'd1) ? 32'd2 : {24'd0, cp_len}));
		dreq(rf_c, sz_of_bytes(cp_len[2:0]), 1'b1, 32'd0, fc_data, 1'b0, 1'b0, DW_TMP, S_CPTOS2);
	end else begin
		tmp2 <= rf_c - ((cp_len == 8'd1) ? 32'd2 : {24'd0, cp_len});
		wreg(4'd15, rf_c - ((cp_len == 8'd1) ? 32'd2 : {24'd0, cp_len}));
		cir_rd(5'h10, sz_of_bytes(cp_len[2:0]), DW_TMP, S_CPSR3);
	end
end
S_CPTOS2: cir_wr(5'h10, sz_of_bytes(cp_len[2:0]), tmp, S_CPWAIT);
S_CPSR3: begin wr(tmp2, sz_of_bytes(cp_len[2:0]), tmp, S_CPWAIT); end
S_CPREG: begin
	// transfer single main processor register
	dw_reg <= {cp_resp[3], cp_resp[2:0]};
	if (!cp_dr) cir_wr(5'h10, `SZ_L, rf_a, S_CPWAIT);
	else cir_rd(5'h10, `SZ_L, DW_REGL, S_CPWAIT);
end
S_CPCTRL: begin : cpctrl
	// control register select code from the register select CIR (UM Table 10-5)
	reg [32:0] cr;
	cr = ctrl_rd(tmp[11:0]);
	if (cr[32]) exc_go(`VEC_CPPROTO, `FMT_CPMID, scan_pc, pc_i);
	else if (!cp_dr) cir_wr(5'h10, `SZ_L, cr[31:0], S_CPWAIT);
	else cir_rd(5'h10, `SZ_L, DW_TMP2, S_CPCTRL2);
end
S_CPCTRL2: begin
	ctrl_wr(tmp[11:0], tmp2);
	state <= S_CPWAIT;
end
S_CPREGS: begin
	// transfer multiple main processor registers: mask D0..D7,A0..A7 (bit 0 = D0)
	mm_mask <= tmp[15:0];
	state <= S_CPREGS2;
end
S_CPREGS2: begin : cpregs2
	reg [3:0] r;
	r = mm_next(mm_mask, 1'b0);
	if (mm_mask == 16'd0) state <= S_CPWAIT;
	else begin
		cnt <= {4'd0, r};
		mm_mask[r] <= 1'b0;
		dw_reg <= r;
		// the register value arrives through port A next clock (cnt): use a
		// two-step: first select, then transfer
		state <= S_CP9;
	end
end
S_CP9: begin
	if (!cp_dr) cir_wr(5'h10, `SZ_L, rf_a, S_CPREGS2);
	else cir_rd(5'h10, `SZ_L, DW_REGL, S_CPREGS2);
end
S_CPMULT: begin
	// transfer multiple coprocessor registers: EA, then the register mask
	if (ir_ea_pi) begin ea <= rf_b; state <= S_CPMULT2; end
	else if (ir_ea_pd) begin ea <= rf_b; state <= S_CPMULT2; end
	else begin ea_ret <= S_CPMULT2; state <= S_EA; end
end
S_CPMULT2: cir_rd(5'h14, `SZ_W, DW_TMP, S_CPMULT3);
S_CPMULT3: begin : cpmult3
	// cnt = operands left; each is cp_len bytes moved in longword parts
	reg [4:0] n;
	reg [11:0] tb;
	n = popcount16(tmp[15:0]);
	tb = (n[0] ? {4'd0, cp_len} : 12'd0) +
	     (n[1] ? {3'd0, cp_len, 1'b0} : 12'd0) +
	     (n[2] ? {2'd0, cp_len, 2'b00} : 12'd0) +
	     (n[3] ? {1'd0, cp_len, 3'b000} : 12'd0) +
	     (n[4] ? {cp_len, 4'b0000} : 12'd0);
	cnt <= {3'd0, n};
	cp_pos <= 8'd0;
	if (ir_ea_pi) wreg({1'b1, ir[2:0]}, rf_b + {20'd0, tb});
	if (ir_ea_pd) begin
		wreg({1'b1, ir[2:0]}, rf_b - {20'd0, tb});
		ea <= rf_b - {24'd0, cp_len};        // first operand at An - length, descending
	end

	state <= S_CPMULT4;
end
S_CPMULT4: begin : cpmult4
	reg [7:0] rem; reg [2:0] chunk;
	rem = cp_len - cp_pos;
	chunk = (rem >= 8'd4) ? 3'd4 : rem[2:0];
	if (cnt == 8'd0) state <= S_CPWAIT;
	else if (rem == 8'd0) begin
		// next operand
		cnt <= cnt - 8'd1;
		cp_pos <= 8'd0;
		if (cnt != 8'd1) ea <= ir_ea_pd ? (ea - {24'd0, cp_len}) : (ea + {24'd0, cp_len});
	end else if (!cp_dr) begin
		cp_pos <= cp_pos + {5'd0, chunk};
		tmp3 <= {14'd0, chunk};
		rd(ea + {24'd0, cp_pos}, sz_of_bytes(chunk), DW_TMP, S_CPSAVE2);
	end else begin
		cp_pos <= cp_pos + {5'd0, chunk};
		tmp3 <= {14'd0, chunk};
		cir_rd(5'h10, sz_of_bytes(chunk), DW_TMP, S_CPREST5);
	end

end
S_CPSAVE2: cir_wr(5'h10, sz_of_bytes(tmp3[2:0]), tmp, S_CPMULT4);
S_CPREST5: wr(ea + {24'd0, cp_pos} - {29'd0, tmp3[2:0]}, sz_of_bytes(tmp3[2:0]), tmp, S_CPMULT4);
S_CPSR: begin
	// transfer status register and scanPC
	if (!cp_dr) begin
		if (cp_resp[8]) cir_wr(5'h18, `SZ_L, scan_pc, S_CPSR2);
		else cir_wr(5'h10, `SZ_W, {16'd0, sr}, S_CPWAIT);
	end else cir_rd(5'h10, `SZ_W, DW_TMP, S_CPSR2);
end
S_CPSR2: begin
	if (!cp_dr) cir_wr(5'h10, `SZ_W, {16'd0, sr}, S_CPWAIT);
	else begin
		sr <= tmp[15:0] & `SR_MASK;
		if (tr_t0) cp_trace_wait <= 1'b1;
		if (cp_resp[8]) cir_rd(5'h18, `SZ_L, DW_TMP, S_CP10);
		else begin flush_req = 1'b1; flush_pc = scan_pc; state <= S_CPWAIT; end
	end
end
S_CP10: begin
	// new scanPC: the pipe refills from it (address error when odd)
	if (tmp[0]) exc_addr_err(tmp);
	else begin flush_req = 1'b1; flush_pc = tmp; state <= S_CPWAIT; end
end

//-------------------------------------------------------------- cpSAVE (UM 10.2.3.3)
S_CPSAVE0: begin
	cp_id <= ir[11:9];
	cpu_flt_fline <= 1'b1;
	dreq({14'd0, 1'b1, 1'b0, ir[11:9], 13'd0} | 32'h04, `SZ_W, 1'b1, 32'd0, `FC_CPU_SPACE, 1'b0, 1'b0, DW_TMP, S_CPSAVE1);
end
S_CPSAVE1: begin : cpsave1
	reg [31:0] base;
	cpu_flt_fline <= 1'b0;
	case (tmp[15:8])
		8'h00: begin
			// empty/reset: only the format word and its reserved word
			if (ir_ea_pd) begin base = rf_b - 32'd4; wreg({1'b1, ir[2:0]}, base); end else base = ea;
			finish;
			wr(base, `SZ_L, {tmp[15:0], 16'd0}, S_FETCH);
		end
		8'h01: begin
			// not ready: service interrupts (pre-instruction frame), read again
			if (irq_pend) begin iack_pc_i <= 1'b1; exc_ilvl <= irq_lvl; state <= S_IACK; end
			else cir_rd(5'h04, `SZ_W, DW_TMP, S_CPSAVE1);
		end
		default: begin
			if (tmp[15:12] == 4'h0 || tmp[1:0] != 2'b00) begin
				// invalid or reserved format, or a length not a multiple of four
				tmp <= {24'd0, `VEC_FMTERR};
				cir_wr(5'h02, `SZ_W, 32'h0001, S_CP_ABORT);
			end else begin
				if (ir_ea_pd) begin base = rf_b - 32'd4 - {24'd0, tmp[7:0]}; wreg({1'b1, ir[2:0]}, base); end else base = ea;
				ea <= base;
				cp_len <= tmp[7:0]; cp_pos <= tmp[7:0];
				wr(base, `SZ_L, {tmp[15:0], 16'd0}, S_CPSV_BODY);
			end
		end
	endcase
end
S_CPSV_BODY: begin
	// state frame entries from the operand CIR to descending addresses (UM Figure 10-14)
	if (cp_pos == 8'd0) finish;
	else cir_rd(5'h10, `SZ_L, DW_TMP, S_CPSV_WR);
end
S_CPSV_WR: begin cp_pos <= cp_pos - 8'd4; wr(ea + {24'd0, cp_pos}, `SZ_L, tmp, S_CPSV_BODY); end

//-------------------------------------------------------------- cpRESTORE (UM 10.2.3.4)
S_CPREST0: begin
	cp_id <= ir[11:9];
	if (ir_ea_pi) ea <= rf_b;
	rd(ir_ea_pi ? rf_b : ea, `SZ_W, DW_TMP, S_CPREST1);
end
S_CPREST1: begin
	cpu_flt_fline <= 1'b1;
	cir_wr(5'h06, `SZ_W, {16'd0, tmp[15:0]}, S_CPREST2);
end
S_CPREST2: begin cpu_flt_fline <= 1'b0; cir_rd(5'h06, `SZ_W, DW_TMP2, S_CPREST3); end
S_CPREST3: begin
	case (tmp2[15:8])
		8'h00: begin
			if (ir_ea_pi) wreg({1'b1, ir[2:0]}, ea + 32'd4);
			finish;
		end
		8'h01: cir_rd(5'h06, `SZ_W, DW_TMP2, S_CPREST3);          // not ready: read again, no interrupts
		default: begin
			if (tmp2[15:12] == 4'h0 || tmp[1:0] != 2'b00) begin
				tmp <= {24'd0, `VEC_FMTERR};
				cir_wr(5'h02, `SZ_W, 32'h0001, S_CP_ABORT);
			end else begin
				cp_len <= tmp[7:0]; cp_pos <= 8'd0;
				if (ir_ea_pi) wreg({1'b1, ir[2:0]}, ea + 32'd4 + {24'd0, tmp[7:0]});
				state <= S_CPRS_BODY;
			end
		end
	endcase
end
S_CPRS_BODY: begin
	// state frame entries from ascending addresses to the operand CIR
	if (cp_pos == cp_len) finish;
	else rd(ea + 32'd4 + {24'd0, cp_pos}, `SZ_L, DW_TMP, S_CPRS_WR);
end
S_CPRS_WR: begin cp_pos <= cp_pos + 8'd4; cir_wr(5'h10, `SZ_L, tmp, S_CPRS_BODY); end

//-------------------------------------------------------------- MMU instructions (UM 9.8, PRM)
S_PMMU0: begin
	// F-line with CpID 0: the second word selects the operation.  An
	// encoding the MC68030 does not support takes the F-line exception here,
	// in supervisor mode (UM 9.8; in user mode the dispatch took the
	// privilege violation).  The supported patterns are the formats of the UM
	// 3.3.3 descriptions (PFLUSH, PLOAD, PMOVE, PTEST: their zero bits, the
	// register and mode fields, control alterable EAs); which reserved bits
	// make an encoding unsupported where the UM does not say follows WinUAE
	// (cpummu030.c mmu_op30_pmove/_pload/_pflush/_ptest: PMOVE R/W=1 with FD;
	// table68k MMUOP030: no PC relative or immediate EA field even for the
	// forms without an operand)
	if (ir[8:6] != 3'b000) exc_pre(`VEC_FLINE);
	else case (ext[15:13])
		3'b000: begin
			// PMOVE TT0/TT1
			if (ext[12:11] != 2'b01 || ext[7:0] != 8'd0 || (ext[9] && ext[8]) || !ir_ea_ctrlalt) exc_pre(`VEC_FLINE);
			else begin ea_ret <= ext[9] ? S_PMOVE_WR : S_PMOVE_RD; state <= S_EA; end
		end
		3'b001: begin
			case (ext[12:10])
				3'b000: begin   // PLOAD
					if (ext[8:5] != 4'd0 || !mmu_fc_ok(ext[4:0]) || !ir_ea_ctrlalt) exc_pre(`VEC_FLINE);
					else begin ea_ret <= S_PLOAD; state <= S_EA; end
				end
				3'b001: begin   // PFLUSHA
					if (ext[9:0] != 10'd0 || ir_ea_pcd || ir_ea_pci || ir_ea_imm || ir_ea_bad) exc_pre(`VEC_FLINE);
					else begin op_req <= 1'b1; op_kind <= 3'd4; state <= S_PFLUSH; end
				end
				3'b100: begin   // PFLUSH by function code
					if (ext[9:8] != 2'd0 || !mmu_fc_ok(ext[4:0]) || ir_ea_pcd || ir_ea_pci || ir_ea_imm || ir_ea_bad) exc_pre(`VEC_FLINE);
					else begin op_req <= 1'b1; op_kind <= 3'd5; op_fc <= mmu_fc(ext[4:0], rf_a[2:0]); op_fcmask <= ext[7:5]; state <= S_PFLUSH; end
				end
				3'b110: begin   // PFLUSH by function code and EA
					if (ext[9:8] != 2'd0 || !mmu_fc_ok(ext[4:0]) || !ir_ea_ctrlalt) exc_pre(`VEC_FLINE);
					else begin ea_ret <= S_PFLUSH2; state <= S_EA; end
				end
				default: exc_pre(`VEC_FLINE);
			endcase
		end
		3'b010: begin
			// PMOVE TC / SRP / CRP
			if (!(ext[12:10] == 3'b000 || ext[12:10] == 3'b010 || ext[12:10] == 3'b011) || ext[7:0] != 8'd0 || (ext[9] && ext[8]) || !ir_ea_ctrlalt)
				exc_pre(`VEC_FLINE);
			else begin ea_ret <= ext[9] ? S_PMOVE_WR : S_PMOVE_RD; state <= S_EA; end
		end
		3'b011: begin
			// PMOVE MMUSR (no FD bit)
			if (ext[12:10] != 3'b000 || ext[8:0] != 9'd0 || !ir_ea_ctrlalt) exc_pre(`VEC_FLINE);
			else begin ea_ret <= ext[9] ? S_PMOVE_WR : S_PMOVE_RD; state <= S_EA; end
		end
		3'b100: begin
			// PTEST
			if (!mmu_fc_ok(ext[4:0]) || !ir_ea_ctrlalt || (ext[8] && ext[12:10] == 3'd0)) exc_pre(`VEC_FLINE);
			else begin ea_ret <= S_PTEST; state <= S_EA; end
		end
		default: exc_pre(`VEC_FLINE);
	endcase
end
S_PLOAD: begin
	op_req <= 1'b1; op_kind <= {2'b00, ~ext[9]}; op_la <= ea; op_fc <= mmu_fc(ext[4:0], rf_a[2:0]);
	state <= S_PFLUSH;
end
S_PFLUSH: begin
	if (op_done) begin
		// translations changed: refill (UM 12.7.1)
		flush_req = 1'b1; flush_pc = scan_pc;
		trace_pend <= tr_t1;
		state <= S_FETCH;
	end
end
S_PFLUSH2: begin
	// PFLUSH fc,#mask,<ea>: the EA is ready
	op_req <= 1'b1; op_kind <= 3'd6; op_la <= ea;
	op_fc <= mmu_fc(ext[4:0], rf_a[2:0]); op_fcmask <= ext[7:5];
	state <= S_PFLUSH;
end
S_PTEST: begin
	op_req <= 1'b1; op_kind <= {2'b01, ~ext[9]}; op_level <= ext[12:10]; op_la <= ea; op_fc <= mmu_fc(ext[4:0], rf_a[2:0]);
	state <= S_PTEST2;
end
S_PTEST2: begin
	if (op_done) begin
		if (ext[8]) wreg({1'b1, ext[7:5]}, op_desc_addr);
		finish;
	end
end
S_PMOVE_RD: begin
	// memory to MMU register
	case (ext[15:13])
		3'b011: rd(ea, `SZ_W, DW_TMP, S_PMOVE_RD3);
		3'b010: begin
			if (ext[12:10] == 3'b000) rd(ea, `SZ_L, DW_TMP, S_PMOVE_RD3);
			else rd(ea, `SZ_L, DW_TMP, S_PMOVE_RD2);
		end
		default: rd(ea, `SZ_L, DW_TMP, S_PMOVE_RD3);
	endcase
end
S_PMOVE_RD2: rd(ea + 32'd4, `SZ_L, DW_TMP2, S_PMOVE_RD3);
S_PMOVE_RD3: begin
	reg_we <= 1'b1;
	reg_fd <= ext[8];
	case (ext[15:13])
		3'b000: begin reg_sel <= ext[10] ? 3'd4 : 3'd3; reg_wdata_lo <= tmp; end
		3'b010: begin
			reg_sel <= (ext[12:10] == 3'b000) ? 3'd0 : (ext[12:10] == 3'b010) ? 3'd1 : 3'd2;
			reg_wdata_hi <= tmp; reg_wdata_lo <= (ext[12:10] == 3'b000) ? tmp : tmp2;
		end
		default: begin reg_sel <= 3'd5; reg_wdata_lo <= tmp; end
	endcase
	sub <= 8'd1;
	state <= S_PMOVE_FIN;
end
S_PMOVE_FIN: begin
	// the MMU reports a configuration error in the second clock after the write
	if (sub[0]) sub <= 8'd0;
	else if (cfg_err) exc_go(`VEC_MMUCONF, `FMT_SIXWORD, scan_pc, pc_i);
	else if (ext[15:13] == 3'b011) finish;
	else begin
		flush_req = 1'b1; flush_pc = scan_pc;       // translation may have changed: refill
		trace_pend <= tr_t1;
		state <= S_FETCH;
	end
end
S_PMOVE_WR: begin
	// MMU register to memory
	case (ext[15:13])
		3'b000: begin finish; wr(ea, `SZ_L, ext[10] ? tt1 : tt0, S_FETCH); end
		3'b011: begin finish; wr(ea, `SZ_W, {16'd0, mmusr}, S_FETCH); end
		default: begin
			if (ext[12:10] == 3'b000) begin finish; wr(ea, `SZ_L, tc, S_FETCH); end
			else begin
				wr(ea, `SZ_L, (ext[12:10] == 3'b010) ? srp_hi : crp_hi, S_PMOVE_WR2);
			end
		end
	endcase
end
S_PMOVE_WR2: begin finish; wr(ea + 32'd4, `SZ_L, (ext[12:10] == 3'b010) ? srp_lo : crp_lo, S_FETCH); end
// ---- end core/ap030_exec_c.vh ----
default: state <= S_FETCH;
endcase
// ---- end core/ap030_exec.vh ----

		if (disp_req) begin
			dispatch;
			// an exception taken at an overlapped dispatch (illegal, privilege,
			// A/F-line) stacks the SR the finishing instruction leaves behind
			if (state == S_GEN_EXEC && g_flags) exc_sr[4:0] <= alu_f;
		end
		if (sf_req) begin
			capture_pipe;
			exc_fa <= 32'd0; exc_dob <= 32'd0; exc_got <= 3'd0; exc_partial <= 32'd0;
			exc_ssw <= {w0_f, sf_need_b & w1_f, ~w0_v | w0_f, ~w1_v | w1_f, 3'b000, 1'b0, 1'b0, 1'b1, 2'b00, 1'b0, fc_prog};
			exc_rk <= sf_boundary ? RK_BOUNDARY : RK_STREAM;
			exc_rs <= state;
			exc_go(`VEC_BUSERR, `FMT_LONGBUS, sf_boundary ? scan_pc : pc_i, 32'd0);
		end

		//---------------------------------------------------------- posted write faults
		// A posted write that failed is a bus error taken at the next
		// instruction boundary (UM 8.1.2), with a short bus fault frame
		// built from its record (exc_late_fault).  Only a frame write of a
		// bus/address error exception failing is a double bus fault and
		// halts (UM 7.5.4, 8.1.2): such an exception waits in S_EXCW until
		// the writes posted before it have completed, so a write fault seen
		// while it stacks (exc_active) is one of its own frame writes.  A
		// fault of an earlier write is kept and taken after the exception
		// in progress, as a bus error of its own; its frame then lies on
		// top and the handler sees it first, before the later fault.
		if (d_late_fault) begin
			if (exc_active && exc_busfault) begin
				late_fault_pend <= 1'b0;
				halted_r <= 1'b1;
				state <= S_HALT;
			end else if ((state == S_EXCW && exc_late) || (state == S_FETCH && late_fault_pend)) begin
				// a write fault is being taken and the write behind it
				// failed too: stack the later one first and keep the earlier
				// one pending, so that the earlier frame lies on top and the
				// faulted writes are rerun in program order
				exc_fa <= f_addr; exc_dob <= f_dob;
				exc_ssw[8:0] <= {1'b1, f_rm, f_rw, f_size, 1'b0, f_fc};
				if (state == S_EXCW) begin lf_fa <= exc_fa; lf_dob <= exc_dob; lf_ssw <= exc_ssw[8:0]; end
				late_fault_pend <= 1'b1;
			end else begin
				late_fault_pend <= 1'b1;
				lf_fa <= f_addr; lf_dob <= f_dob;
				lf_ssw <= {1'b1, f_rm, f_rw, f_size, 1'b0, f_fc};   // DF RM RW SIZE 0 FC
			end
		end

		//---------------------------------------------------------- prefetch and pipe maintenance
		tm_pop <= pop_n;
		if (flush_req || pipe_load) begin tm_flush <= 1'b1; due_v <= 1'b0; end
		if (flush_req) begin
			pq_v <= 6'd0; pq_f <= 6'd0; pq_n <= 3'd0;
			scan_pc <= flush_pc;
			fetch_pc <= {flush_pc[31:2], 2'b00};
			fetch_skip <= flush_pc[1];
			// whatever is still outstanding belongs to the old stream
			fetch_out <= fetch_out - {1'b0, i_ack | i_fault};
			fetch_disc <= fetch_out - {1'b0, i_ack | i_fault};
			refill_p <= 1'b0;
			// Ordinary branches preserve the program function code. Issue
			// their target fetch with the redirect, retaining the discard
			// count for older requests. Exception/RTE/SR changes use the
			// existing path so their new program space is selected first.
			if ((state == S_BCC || state == S_JMP || state == S_RTS2 ||
			     state == S_RTD2 || state == S_DBCC || (state == S_DWAIT && dw_ret == S_JMP)) && i_ready &&
			    (fetch_out - {1'b0, i_ack | i_fault} != 2'd2) &&
			    !halted_r && !fetch_hold) begin
				i_stb <= 1'b1;
				i_addr <= {flush_pc[31:2], 2'b00};
				i_fc <= fc_prog;
				fetch_pc <= {flush_pc[31:2], 2'b00} + 32'd4;
				fetch_out <= fetch_out - {1'b0, i_ack | i_fault} + 2'd1;
			end
		end else if (pipe_load) begin
			// RTE: stages C and B from the frame, fetching resumes behind them
			begin : pipe_preload
				reg [31:0] resume_fetch;
				resume_fetch = flush_pc + (pipe_c_v ? (pipe_b_v ? 32'd4 : 32'd2) : 32'd0);
				pq[0] <= pipe_c; pq[1] <= pipe_b;
				pq_v <= {4'd0, pipe_b_v & pipe_c_v, pipe_c_v};
				pq_f <= 6'd0;
				pq_n <= pipe_c_v ? (pipe_b_v ? 3'd2 : 3'd1) : 3'd0;
				scan_pc <= flush_pc;
				fetch_pc <= {resume_fetch[31:2], 2'b00};
				fetch_skip <= resume_fetch[1];
			end
			fetch_out <= fetch_out - {1'b0, i_ack | i_fault};
			fetch_disc <= fetch_out - {1'b0, i_ack | i_fault};
			refill_p <= 1'b0;
		end else begin
			// pop, then append the fetched words, then issue the next fetch
			begin : pipe_update
				reg [15:0] nq [0:5];
				reg [5:0] nv, nf;
				reg [2:0] nn;
				reg ret, disc_now;
				reg due_now;
				reg [31:0] due_at;
				reg [1:0] out_after, disc_after, live;
				integer j;
				ret = i_ack | i_fault;                    // a fetch returns this clock
				disc_now = ret && (fetch_disc != 2'd0);   // ... from a flushed stream
				out_after = fetch_out - {1'b0, ret};
				disc_after = fetch_disc - {1'b0, disc_now};
				live = out_after - disc_after;            // fetches that will still append words
				for (j = 0; j < 6; j = j + 1) begin nq[j] = pq[j]; nv[j] = pq_v[j]; nf[j] = pq_f[j]; end
				nn = pq_n;
				if (pop_n != 0) begin
					for (j = 0; j < 6; j = j + 1) begin
						if (j + pop_n < 6) begin nq[j] = pq[j + pop_n]; nv[j] = pq_v[j + pop_n]; nf[j] = pq_f[j + pop_n]; end
						else begin nq[j] = 16'd0; nv[j] = 1'b0; nf[j] = 1'b0; end
					end
					nn = pq_n - pop_n;
					scan_pc <= scan_pc + {29'd0, pop_n, 1'b0};
				end
				if (ret && !disc_now) begin
					if (!fetch_skip) begin
						nq[nn] = i_data[31:16]; nv[nn] = 1'b1; nf[nn] = i_fault; nn = nn + 3'd1;
					end
					nq[nn] = i_data[15:0]; nv[nn] = 1'b1; nf[nn] = i_fault; nn = nn + 3'd1;
					fetch_skip <= 1'b0;
				end
				for (j = 0; j < 6; j = j + 1) begin pq[j] <= nq[j]; pq_v[j] <= nv[j]; pq_f[j] <= nf[j]; end
				pq_n <= nn;
				fetch_disc <= disc_after;
				// another longword when the queue has room for everything in flight
				// and the memory system can take it (two fetches at most); with
				// fetch_lazy only when two words or fewer are left, not past the
				// pipeline model's stop point (a stop is on a branch whose words are
				// queued and which flushes the queue) and not before the model has
				// scanned.  Should the sequencer wait 63 clocks for a word that is
				// neither queued nor on the way, the stop and the scan wait are
				// ignored, so no model input can hang the processor; a stop that
				// holds while the sequencer has its words (a long instruction
				// before the branch) is kept
				if (fetch_lazy && pipe_consumer && (pop_n == 2'd0) && (nn + {live, 1'b0} < 3'd2)) begin
					if (!stop_starve) stop_wait <= stop_wait + 6'd1;
				end else stop_wait <= 6'd0;
				// the model decides at the consumption where this fetch became
				// due (Hatari fetches there, its scan two words ahead)
				due_now = nn + {live, 1'b0} <= (fetch_lazy ? 3'd2 : 3'd4);
				due_at  = due_v ? due_scan : scan_pc + {29'd0, pop_n, 1'b0};
				if (due_now && !due_v) begin due_v <= 1'b1; due_scan <= due_at; end
				// none during exception processing: S is set at its start and the old
				// stream is discarded at its end, so a fetch now would carry the new
				// program space to the old stream's address (a user address fetched as
				// supervisor program, which a transparent window passes untranslated)
				if (out_after != 2'd2 && i_ready && !halted_r && !fetch_hold && due_now &&
				    !exc_active && state != S_EXC0 &&
				    (!fetch_lazy || stop_starve ||
				     (due_v ? fetch_model_allow[4] : fetch_model_allow[pop_n]))) begin
					due_v <= 1'b0;
					i_stb <= 1'b1;
					i_fc <= fc_prog;
					fetch_pc <= fetch_pc + 32'd4;
					fetch_out <= out_after + 2'd1;
				end else fetch_out <= out_after;
			end
		end
	end
end

endmodule
