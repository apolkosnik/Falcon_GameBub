// Game Bub Falcon: the Game Bub host (MCU) interface.
//
// Host memory map (byte addresses on the HostV0 memory interface):
//
//   0x0000_0000           ID, read only: "FALC"
//   0x0000_0004           version, read only
//   0x0000_0010..2C       debug, read only: 10 state ({TOS loaded, RAM TOS,
//                         disks ready, NVRAM restored, halted}), 14 first
//                         long word of TOS, 18 blocks read, 1C blocks
//                         written, 20 disk server state and slots mounted,
//                         24 picture geometry (gb_fb), 28 frame store
//                         (scan lines fetched, late, queue overflow), 2C
//                         SDRAM commands
//   0x0000_1000, 1004     statistics: clocks the Falcon was paused / ran since
//                         the last write (the firmware's convention)
//   0x0000_1030           mouse motion {dy, dx}, signed 16 bit, right and
//                         down positive  \  written by the firmware fork for
//   0x0000_1034           mouse buttons   |  a mouse and keyboard on the dock,
//   0x0000_1038           keyboard event  |  as for the Game Bub Minimig core
//                         (USB HID usage 7:0, bit 8 pressed)
//   0x0000_103C           mouse wheel    /  (not used by the Falcon)
//   0x0000_1040..107C     settings (metadata/settings.json), read / write;
//                         0x1070 the 68060 variant's Fast RAM (0 off, 1 32 MB)
//   0x2000_0000..7FFFF    TOS (files.json id 0) -> $E00000 through
//                         falcon_system's loader (byte writes)
//   0x2100_0000..1FFFF    cartridge (id 8, optional) -> $FA0000
//   0x3000_0000..3FFF     the disks' buffer (gb_disk; ids 1..6 on demand)
//   0x4000_0000..33       the NVRAM file (id 7): the MC146818's 50 bytes as
//                         MiSTer and Hatari save them (registers 14..63).
//                         Written: kept and given to the Falcon at its start;
//                         read: the Falcon's NVRAM as it is
//   0xF000_0000..0C       HostV0 command parameters / results
//   0xF000_1000..14       core -> host command and its parameters (read),
//                         results (write): gb_disk's file commands
//
// File data arrives as 32 bit words with byte 0 of the file in bits 7:0.
//
// Running: the Falcon is held in reset until CoreRun (after the files are
// loaded) and again from CoreHalt (the firmware sends CoreHalt then CoreRun
// for its Reset, CoreHalt alone before it saves and leaves). At the first
// CoreRun the NVRAM file (unless it is empty: all its bytes 0xFF, as the
// firmware gives a file it creates, or 0x00) is written into the Falcon's
// NVRAM after its default image is built, and the disks are mounted. The Reset setting resets the Falcon, Cold reset also clears
// TOS's warm start flag, Reset NVRAM builds the default NVRAM again.
//
// SPDX-License-Identifier: GPL-2.0-or-later

module gb_host
(
	input             clk,
	input             reset,

	// HostV0 memory interface
	input      [31:0] mem_address,
	input             mem_enable,
	input             mem_write,
	output reg [31:0] mem_dataRead,
	input      [31:0] mem_dataWrite,
	output reg        mem_done,

	// HostV0 host -> core command channel
	input             cmd_request,
	output            cmd_busy,
	output            cmd_done,
	output            cmd_error,

	// falcon_system's loader
	output reg        ld_wr = 1'b0,
	output reg [23:0] ld_addr = 24'd0,
	output reg  [7:0] ld_data = 8'd0,
	input             ld_busy,

	// the Falcon's NVRAM port (falcon_nvram)
	output reg        nv_init = 1'b0,
	input             nv_ready,
	output      [5:0] nv_addr,
	output reg  [7:0] nv_din = 8'd0,
	output reg        nv_wr = 1'b0,
	input       [7:0] nv_dout,

	// core control
	output            core_reset,     // hold the Falcon in reset
	output reg        cold_reset = 1'b0,   // a pulse (with core_reset): power on
	output reg        tos_loaded = 1'b0,
	output reg        ram_tos = 1'b0, // the TOS loaded is a RAM TOS (TOS 4.92)
	output reg        disk_start = 1'b0,   // a pulse: mount the disks
	input             disk_ready,
	output reg        focus = 1'b1,

	// settings
	output reg  [1:0] set_monitor,    // 0 VGA, 1 RGB, 2 TV, 3 mono
	output reg        set_ram4,       // 4 MB of ST-RAM (else 14)
	output reg        set_falcon_speed,   // the Falcon's 16 MHz (else 32 MHz turbo)
	output reg  [7:0] key_x,          // USB HID usages of the buttons' keys
	output reg  [7:0] key_y,
	output reg  [7:0] key_start,
	output reg  [7:0] key_select,
	output reg        sram_safe,
	output reg  [1:0] mouse_speed,
	output reg        set_fast_ram,   // the 68060 variant: 32 MB of Fast RAM (CT60 mode)

	// mouse and keyboard from the host (firmware)
	output reg        hmouse_valid,
	output reg [15:0] hmouse_dx,
	output reg [15:0] hmouse_dy,
	output reg  [2:0] hmouse_btn,
	output reg        hkey_valid,
	output reg  [7:0] hkey_usage,
	output reg        hkey_down,

	// core -> host command words and results (gb_disk)
	input      [31:0] hc_cmd,
	input      [31:0] hc_p1, hc_p2, hc_p3, hc_p4, hc_p5,
	output reg [31:0] hc_res0, hc_res1, hc_res2,

	// the disks' buffer (gb_disk)
	output reg [11:0] hb_addr,
	output reg        hb_we,
	output reg [31:0] hb_wdata,
	input      [31:0] hb_rdata,

	// statistics
	input             stat_run,
	input             stat_stall,

	// debug
	input      [31:0] dbg_read,
	input      [31:0] dbg_written,
	input      [31:0] dbg_disk,
	input      [31:0] dbg_geom,
	input      [31:0] dbg_fb,
	input      [31:0] dbg_sdram
);

localparam [15:0] CMD_GET_STATUS     = 16'h0000;
localparam [15:0] CMD_CORE_RUN       = 16'h0100;
localparam [15:0] CMD_CORE_HALT      = 16'h0101;
localparam [15:0] CMD_SETUP_COMPLETE = 16'h0102;
localparam [15:0] CMD_NOTIFY_FOCUS   = 16'h0200;
localparam [15:0] CMD_FILE_WR_START  = 16'h0300;
localparam [15:0] CMD_FILE_WR_END    = 16'h0301;
localparam [15:0] CMD_FILE_RD_START  = 16'h0302;
localparam [15:0] CMD_FILE_RD_END    = 16'h0303;

localparam [2:0] STATUS_SETUP = 3'd2, STATUS_CORE_HALT = 3'd3, STATUS_CORE_RUN = 3'd4;
localparam [15:0] TOS_ID = 16'd0, NVRAM_ID = 16'd7, CART_ID = 16'd8;

// ------------------------------------------------------------- settings
reg [7:0] s_monitor, s_ram, s_speed, s_safe, s_mouse, s_fast;
always @* begin
	set_monitor      = s_monitor[1:0];
	set_ram4         = s_ram[0];
	set_falcon_speed = s_speed[0];
	sram_safe        = s_safe[0];
	mouse_speed      = s_mouse[1:0];
	set_fast_ram     = s_fast[0];
end

// --------------------------------------------------------- NVRAM image
reg  [7:0] nv_img [0:63];
reg        nv_any;               // the file has a byte other than 0xFF / 0x00
reg  [5:0] nv_ptr = 6'd0;
reg  [5:0] nv_raddr = 6'd0;
reg        nv_restoring = 1'b0;
reg        nv_restored = 1'b0;
reg  [1:0] nv_step = 2'd0;
assign nv_addr = nv_restoring ? nv_ptr : nv_raddr;

// ------------------------------------------------------ command channel
reg [31:0] reg_p0, reg_p1, reg_p2, reg_p3;
reg  [1:0] cmd_state;
reg  [2:0] status;
reg        setup_done;
reg        halted;
reg        reset_req;     // the Reset setting: a reset pulse
reg  [7:0] rst_cnt;       // the reset pulse's length
reg        run_go;        // CoreRun: restore the NVRAM, mount, run
reg        disks_started;
reg [31:0] tos_first;

assign cmd_busy  = (cmd_state == 2'd1);
assign cmd_done  = (cmd_state == 2'd2);
assign cmd_error = (cmd_state == 2'd3);

reg disk_ready_seen;
assign core_reset = halted || run_go || nv_restoring || !disk_ready_seen || rst_cnt != 8'd0 || !tos_loaded;

// ---------------------------------------------------------- statistics
reg [31:0] stat_stalls, stat_cycles;
reg  [1:0] stat_clr;
always @(posedge clk) begin
	if (reset || stat_clr[0]) stat_stalls <= 32'd0;
	else if (stat_stall && stat_stalls != 32'hFFFFFFFF) stat_stalls <= stat_stalls + 32'd1;
	if (reset || stat_clr[1]) stat_cycles <= 32'd0;
	else if (stat_run && stat_cycles != 32'hFFFFFFFF) stat_cycles <= stat_cycles + 32'd1;
end

// ------------------------------------------------------- memory access
localparam [2:0] M_IDLE = 3'd0, M_LD = 3'd1, M_LDW = 3'd2, M_DONE = 3'd3, M_B0 = 3'd4, M_B1 = 3'd5,
                 M_NV = 3'd6;
reg  [2:0] mstate;
reg [31:0] m_wdata;
reg  [1:0] m_byte;
reg  [1:0] m_wait;

wire        is_reg   = (mem_address[31:16] == 16'h0000);
wire        is_tos   = (mem_address[31:19] == 13'h0400);       // 0x2000_0000..7FFFF
wire        is_cart  = (mem_address[31:17] == 15'h1080);       // 0x2100_0000..1FFFF
wire        is_cmd   = (mem_address[31:4] == 28'hF000000);
wire        is_ccmd  = (mem_address[31:5] == 27'h7800080);     // 0xF000_1000..1F
wire        is_buf   = (mem_address[31:14] == 18'h0C000);      // 0x3000_0000..3FFF
wire        is_nv    = (mem_address[31:6] == 26'h1000000);     // 0x4000_0000..3F

function automatic [31:0] reg_read(input [15:0] a);
	case (a)
		16'h0000: reg_read = 32'h46414C43;   // "FALC"
		16'h0004: reg_read = 32'h00000100;   // version 0.1
		16'h0010: reg_read = {26'd0, ram_tos, tos_loaded, disk_ready_seen, nv_restored, halted, nv_any};
		16'h0014: reg_read = tos_first;
		16'h0018: reg_read = dbg_read;
		16'h001C: reg_read = dbg_written;
		16'h0020: reg_read = dbg_disk;
		16'h0024: reg_read = dbg_geom;
		16'h0028: reg_read = dbg_fb;
		16'h002C: reg_read = dbg_sdram;
		16'h1000: reg_read = stat_stalls;
		16'h1004: reg_read = stat_cycles;
		16'h1030: reg_read = {hmouse_dy, hmouse_dx};
		16'h1034: reg_read = {29'd0, hmouse_btn};
		16'h1040: reg_read = 32'd0;           // Reset (action)
		16'h1044: reg_read = {24'd0, s_monitor};
		16'h1048: reg_read = {24'd0, s_ram};
		16'h104C: reg_read = {24'd0, s_speed};
		16'h1050: reg_read = {24'd0, key_x};
		16'h1054: reg_read = {24'd0, key_y};
		16'h1058: reg_read = {24'd0, key_start};
		16'h105C: reg_read = {24'd0, key_select};
		16'h1060: reg_read = {24'd0, s_mouse};
		16'h1064: reg_read = {24'd0, s_safe};
		16'h1068: reg_read = 32'd0;           // Cold reset (action)
		16'h106C: reg_read = 32'd0;           // Reset NVRAM (action)
		16'h1070: reg_read = {24'd0, s_fast};
		default:  reg_read = 32'd0;
	endcase
endfunction

integer i;
always @(posedge clk) begin
	mem_done     <= 1'b0;
	hmouse_valid <= 1'b0;
	hkey_valid   <= 1'b0;
	stat_clr     <= 2'b00;
	hb_we        <= 1'b0;
	ld_wr        <= 1'b0;
	nv_wr        <= 1'b0;
	nv_init      <= 1'b0;
	disk_start   <= 1'b0;
	cold_reset   <= 1'b0;
	if (rst_cnt != 8'd0) rst_cnt <= rst_cnt - 8'd1;
	if (disk_ready) disk_ready_seen <= 1'b1;

	if (reset) begin
		hc_res0 <= 32'd0; hc_res1 <= 32'd0; hc_res2 <= 32'd0;
		mstate      <= M_IDLE;
		cmd_state   <= 2'd0;
		status      <= STATUS_SETUP;
		setup_done  <= 1'b0;
		halted      <= 1'b1;
		focus       <= 1'b1;
		reset_req   <= 1'b0;
		rst_cnt     <= 8'd0;
		run_go      <= 1'b0;
		disks_started <= 1'b0;
		disk_ready_seen <= 1'b0;
		tos_loaded  <= 1'b0;
		ram_tos     <= 1'b0;
		tos_first   <= 32'd0;
		nv_any      <= 1'b0;
		nv_restoring <= 1'b0;
		nv_restored <= 1'b0;
		s_monitor   <= 8'd0;
		s_ram       <= 8'd0;
		s_speed     <= 8'd0;
		s_safe      <= 8'd0;
		s_mouse     <= 8'd1;
		s_fast      <= 8'd1;
		key_x       <= 8'h2C;   // Space
		key_y       <= 8'h28;   // Return
		key_start   <= 8'h44;   // F11: Help
		key_select  <= 8'h29;   // Esc
		hmouse_dx   <= 16'd0;
		hmouse_dy   <= 16'd0;
		hmouse_btn  <= 3'd0;
	end
	else begin
		// ---------------------------------------------- CoreRun: NVRAM, disks
		if (run_go && !nv_restoring) begin
			if (!disks_started) begin
				disks_started <= 1'b1;
				disk_start    <= 1'b1;
			end
			if (nv_any && !nv_restored) begin
				// at the first run: the default image is built while the
				// Falcon is in reset; once it is ready, the file's bytes go
				// over it (a later CoreRun, the firmware's Reset, keeps the
				// NVRAM as the Falcon left it)
				nv_restoring <= 1'b1;
				nv_ptr  <= 6'd0;
				nv_step <= 2'd0;
			end
			run_go <= 1'b0;
		end
		if (nv_restoring) begin
			case (nv_step)
				2'd0: if (nv_ready) nv_step <= 2'd1;
				2'd1: begin
					nv_din  <= nv_img[nv_ptr];
					nv_wr   <= 1'b1;
					nv_step <= 2'd2;
				end
				2'd2: begin
					if (nv_ptr == 6'd49) begin nv_restoring <= 1'b0; nv_restored <= 1'b1; end
					else begin nv_ptr <= nv_ptr + 6'd1; nv_step <= 2'd1; end
				end
				default: nv_step <= 2'd0;
			endcase
		end
		if (reset_req) begin
			reset_req <= 1'b0;
			rst_cnt   <= 8'd255;
		end

		// ---------------------------------------------- memory interface
		case (mstate)
		// The framework (SpiReceiverFifo) keeps enable high from one request
		// to the next, also in the clock that done is high: the request seen
		// then is the one just completed, so a new one starts only after it.
		M_IDLE:
			if (mem_enable && !mem_done) begin
				if (is_tos || is_cart) begin
					if (mem_write) begin
						if (is_tos && mem_address[18:0] == 19'd0) begin
							tos_first <= mem_dataWrite;
							// a RAM TOS starts with move #$2700,sr ($46FC2700)
							ram_tos   <= (mem_dataWrite == 32'h0027FC46);
						end
						ld_addr <= is_tos ? {5'b11100, mem_address[18:0]} : {7'b1111101, mem_address[16:0]};
						m_wdata <= mem_dataWrite;
						m_byte  <= 2'd0;
						mstate  <= M_LD;
					end
					else begin
						mem_dataRead <= 32'd0;
						mstate <= M_DONE;
					end
				end
				else if (is_buf) begin
					hb_addr  <= mem_address[13:2];
					hb_wdata <= mem_dataWrite;
					hb_we    <= mem_write;
					mstate   <= M_B0;
				end
				else if (is_nv) begin
					if (mem_write) begin
						for (i = 0; i < 4; i = i + 1) begin
							nv_img[{mem_address[5:2], 2'(i)}] <= mem_dataWrite[8 * i +: 8];
							if (mem_dataWrite[8 * i +: 8] != 8'hFF && mem_dataWrite[8 * i +: 8] != 8'h00 &&
							    {mem_address[5:2], 2'(i)} < 6'd50) nv_any <= 1'b1;
						end
						mstate <= M_DONE;
					end
					else begin
						nv_raddr <= {mem_address[5:2], 2'd0};
						m_byte   <= 2'd0;
						mstate   <= M_NV;
					end
				end
				else begin
					if (mem_write) begin
						if (is_cmd) case (mem_address[3:2])
							2'd0: reg_p0 <= mem_dataWrite;
							2'd1: reg_p1 <= mem_dataWrite;
							2'd2: reg_p2 <= mem_dataWrite;
							2'd3: reg_p3 <= mem_dataWrite;
						endcase
						else if (is_ccmd) case (mem_address[4:2])
							3'd0: hc_res0 <= mem_dataWrite;
							3'd1: hc_res1 <= mem_dataWrite;
							3'd2: hc_res2 <= mem_dataWrite;
							default: ;
						endcase
						else if (is_reg) case (mem_address[15:0])
							16'h1000: stat_clr[0] <= 1'b1;
							16'h1004: stat_clr[1] <= 1'b1;
							16'h1030: begin
								hmouse_valid <= 1'b1;
								hmouse_dx    <= mem_dataWrite[15:0];
								hmouse_dy    <= mem_dataWrite[31:16];
							end
							16'h1034: hmouse_btn <= mem_dataWrite[2:0];
							16'h1038: begin
								hkey_valid <= 1'b1;
								hkey_usage <= mem_dataWrite[7:0];
								hkey_down  <= mem_dataWrite[8];
							end
							16'h1040: if (mem_dataWrite != 32'd0) reset_req <= 1'b1;
							16'h1044: s_monitor  <= mem_dataWrite[7:0];
							16'h1048: s_ram      <= mem_dataWrite[7:0];
							16'h104C: s_speed    <= mem_dataWrite[7:0];
							16'h1050: key_x      <= mem_dataWrite[7:0];
							16'h1054: key_y      <= mem_dataWrite[7:0];
							16'h1058: key_start  <= mem_dataWrite[7:0];
							16'h105C: key_select <= mem_dataWrite[7:0];
							16'h1060: s_mouse    <= mem_dataWrite[7:0];
							16'h1064: s_safe     <= mem_dataWrite[7:0];
							16'h1068: if (mem_dataWrite != 32'd0) begin reset_req <= 1'b1; cold_reset <= 1'b1; end
							16'h106C: if (mem_dataWrite != 32'd0) begin reset_req <= 1'b1; nv_init <= 1'b1; end
							16'h1070: s_fast     <= mem_dataWrite[7:0];
							default: ;
						endcase
					end
					else begin
						if (is_cmd) case (mem_address[3:2])
							2'd0: mem_dataRead <= reg_p0;
							2'd1: mem_dataRead <= reg_p1;
							2'd2: mem_dataRead <= reg_p2;
							2'd3: mem_dataRead <= reg_p3;
						endcase
						else if (is_ccmd) case (mem_address[4:2])
							3'd0: mem_dataRead <= hc_cmd;
							3'd1: mem_dataRead <= hc_p1;
							3'd2: mem_dataRead <= hc_p2;
							3'd3: mem_dataRead <= hc_p3;
							3'd4: mem_dataRead <= hc_p4;
							3'd5: mem_dataRead <= hc_p5;
							default: mem_dataRead <= 32'd0;
						endcase
						else if (is_reg) mem_dataRead <= reg_read(mem_address[15:0]);
						else mem_dataRead <= 32'd0;
					end
					mstate <= M_DONE;
				end
			end

		// the four bytes of a word to the loader (it shows busy a clock
		// after a byte is taken)
		M_LD:
			if (!ld_busy) begin
				ld_wr   <= 1'b1;
				ld_data <= m_wdata[8 * m_byte +: 8];
				m_wait  <= 2'd2;
				mstate  <= M_LDW;
			end
		M_LDW:
			if (m_wait != 2'd0) m_wait <= m_wait - 2'd1;
			else if (m_byte == 2'd3) mstate <= M_DONE;
			else begin
				m_byte  <= m_byte + 2'd1;
				ld_addr <= ld_addr + 24'd1;
				mstate  <= M_LD;
			end

		// the NVRAM's bytes (nv_dout follows nv_addr)
		M_NV: begin
			if (m_wait == 2'd0) m_wait <= 2'd1;
			else begin
				m_wait <= 2'd0;
				mem_dataRead[8 * m_byte +: 8] <= nv_dout;
				if (m_byte == 2'd3) mstate <= M_DONE;
				else begin
					m_byte   <= m_byte + 2'd1;
					nv_raddr <= nv_raddr + 6'd1;
				end
			end
		end

		// the disks' buffer (block RAM: the read data follows the address)
		M_B0: mstate <= M_B1;
		M_B1: begin
			mem_dataRead <= hb_rdata;
			mstate       <= M_DONE;
		end

		M_DONE: begin
			mem_done <= 1'b1;
			mstate   <= M_IDLE;
		end
		default: mstate <= M_IDLE;
		endcase

		// ---------------------------------------------- command channel
		if (cmd_request) begin
			if (cmd_state == 2'd0) begin
				cmd_state <= 2'd2;
				reg_p0    <= 32'd0;
				case (reg_p0[15:0])
					CMD_GET_STATUS: reg_p0 <= {29'd0, status};

					CMD_SETUP_COMPLETE: begin
						setup_done <= 1'b1;
						if (status == STATUS_SETUP) status <= STATUS_CORE_HALT;
					end

					CMD_CORE_RUN:
						if (!setup_done) cmd_state <= 2'd3;
						else if (status != STATUS_CORE_RUN) begin
							status <= STATUS_CORE_RUN;
							halted <= 1'b0;
							run_go <= 1'b1;
						end

					CMD_CORE_HALT: begin
						if (setup_done) status <= STATUS_CORE_HALT;
						halted <= 1'b1;
					end

					CMD_NOTIFY_FOCUS: focus <= reg_p1[0];

					CMD_FILE_WR_START:
						if (reg_p1[15:0] == TOS_ID) tos_loaded <= 1'b0;
						else if (reg_p1[15:0] == NVRAM_ID) nv_any <= 1'b0;

					CMD_FILE_WR_END:
						if (reg_p1[15:0] == TOS_ID) begin
							tos_loaded <= (reg_p2 != 32'd0);
							cold_reset <= 1'b1;
						end

					// saving: the NVRAM file is its 50 bytes; nothing else is
					// read back (the disks are written as the Falcon writes)
					CMD_FILE_RD_START:
						reg_p0 <= (reg_p1[15:0] == NVRAM_ID) ? 32'd50 : 32'd0;

					CMD_FILE_RD_END: ;

					default: cmd_state <= 2'd3;
				endcase
			end
		end
		else cmd_state <= 2'd0;
	end
end

endmodule
