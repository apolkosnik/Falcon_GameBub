// Game Bub Falcon: the disks. falcon_system asks for 512-byte blocks the
// way MiSTer's hps_io serves them (slots 0 floppy A, 1 floppy B, 2 IDE
// master, 3 IDE slave, 4 SCSI 0, 5 SCSI 1; 6, the SCSI CD-ROM, is never
// mounted here, but its requests are served as an empty image's: falcon_scsi
// answers selection at ID 2 with no medium and asks slot 6 for its INQUIRY,
// READ CAPACITY and MODE SENSE window blocks; unanswered, the target kept BSY
// and every later SCSI selection waited for a free bus until it timed out);
// this module serves them from the image files on the
// microSD card with the framework's on-demand file commands (FileGetSize,
// FileRead, FileWrite, FileFlush), through a 16 KB buffer that the firmware
// reads and writes over the host memory interface (gb_host, 0x3000_0000).
// Slot n is files.json id FILE_ID0 + n.
//
// The protocol on the Falcon's side (as hps_io, and as Falcon_MiSTer's
// bench tb/system/sim_main.cpp plays it): a request is sd_rd[n] or sd_wr[n]
// held with sd_lba[n] and sd_blk_cnt[n] (blocks - 1). sd_ack[n] goes high
// for the transfer: a read gives every byte with sd_buff_wr (sd_buff_addr,
// sd_buff_dout), one every other clock; a write puts out sd_buff_addr and
// takes the byte from sd_buff_din[n] two clocks later. sd_ack[n] then goes
// low, and the next request of the slot is taken once sd_rd[n] / sd_wr[n]
// have gone low. One request at a time; slots are served in turn.
//
// After `start` (the first CoreRun) every slot's file is asked for its size
// (FileGetSize); a slot with a file of 512 bytes or more is mounted with an
// img_mounted pulse and its size; `ready` follows the last. The first
// command waits HOST_TIME clocks at most for an answer (no host: nothing is
// mounted). Bytes of a block beyond the end of the file read as 0, and are
// not written: so are the Falcon SCSI target's "window" blocks (LBAs above
// any image, served by Main_MiSTer on MiSTer; falcon_scsi then answers from
// its own defaults). A slot written to is flushed (FileFlush) a second after
// its last write.
//
// File data in host words: file byte 4k + i in bits 8i+7:8i of word k.
//
// SPDX-License-Identifier: GPL-2.0-or-later

module gb_disk
#(
	parameter integer CLK_HZ    = 31979167,
	parameter [15:0]  FILE_ID0  = 16'd1,
	parameter [31:0]  BUF_ADDR  = 32'h3000_0000,
	parameter [27:0]  HOST_TIME = 28'd150000000      // ~4.7 s
)
(
	input             clk,
	input             reset,
	input             start,          // a pulse: mount the images
	output reg        ready = 1'b0,   // mounting done

	// falcon_system's disk port
	output reg  [6:0] img_mounted = 7'd0,
	output            img_readonly,
	output reg [63:0] img_size = 64'd0,
	input      [31:0] sd_lba [7],
	input       [6:0] sd_rd,
	input       [6:0] sd_wr,
	input       [5:0] sd_blk_cnt [7],
	output reg  [6:0] sd_ack = 7'd0,
	output reg [13:0] sd_buff_addr = 14'd0,
	output reg  [7:0] sd_buff_dout = 8'd0,
	input       [7:0] sd_buff_din [7],
	output reg        sd_buff_wr = 1'b0,

	// core -> host command (gb_host)
	output reg        hc_request = 1'b0,
	output reg [31:0] hc_cmd = 32'd0,
	output reg [31:0] hc_p1 = 32'd0, hc_p2 = 32'd0, hc_p3 = 32'd0, hc_p4 = 32'd0, hc_p5 = 32'd0,
	input             hc_done,
	input             hc_error,
	input      [31:0] hc_res0, hc_res1, hc_res2,

	// the buffer, host side (gb_host: 0x3000_0000..3FFF, words)
	input      [11:0] hb_addr,
	input             hb_we,
	input      [31:0] hb_wdata,
	output reg [31:0] hb_rdata,

	// observation
	output reg [31:0] dbg_read = 32'd0,      // blocks read
	output reg [31:0] dbg_written = 32'd0,   // blocks written
	output reg  [5:0] dbg_mounted = 6'd0,
	output reg  [7:0] dbg_state = 8'd0       // {error seen, slot, state}
);

assign img_readonly = 1'b0;

localparam [31:0] CMD_FILE_GET_SIZE = 32'h0400, CMD_FILE_READ = 32'h0402,
                  CMD_FILE_WRITE = 32'h0403, CMD_FILE_FLUSH = 32'h0404;
localparam integer FLUSH_TIME = CLK_HZ;

// ------------------------------------------------------------- buffer
reg [31:0] buf_m [0:4095];
reg [11:0] b_addr;
reg        b_we = 1'b0;
reg [31:0] b_wdata;
reg [31:0] b_q;
always @(posedge clk) begin
	if (hb_we) buf_m[hb_addr] <= hb_wdata;
	hb_rdata <= buf_m[hb_addr];
end
always @(posedge clk) begin
	if (b_we) buf_m[b_addr] <= b_wdata;
	b_q <= buf_m[b_addr];
end

// ------------------------------------------------------------- slots
reg [40:0] size [0:6];            // bytes (an image of up to 2 TB; slot 6 always 0)
reg  [5:0] dirty = 6'd0;
reg [27:0] flush_cnt = 28'd0;

localparam [4:0] S_IDLE = 5'd0, S_MOUNT = 5'd1, S_MOUNT2 = 5'd2, S_REQ = 5'd3,
                 S_RD_CMD = 5'd4, S_RD_WAIT = 5'd5, S_RD_ACK = 5'd6, S_RD_ADDR = 5'd7,
                 S_RD_BYTE = 5'd8, S_WR_ACK = 5'd9, S_WR_ADDR = 5'd10, S_WR_WAIT = 5'd11,
                 S_WR_BYTE = 5'd12, S_WR_CMD = 5'd13, S_END = 5'd14, S_DROP = 5'd15,
                 S_HC0 = 5'd16, S_HC1 = 5'd17, S_HC2 = 5'd18, S_FLUSH = 5'd19, S_MOUNT3 = 5'd20;
reg  [4:0] state = S_IDLE, ret;
reg  [2:0] slot = 3'd0;           // slot served / mounted
reg  [2:0] rr = 3'd0;             // next slot to look at
reg        mounting = 1'b0;
reg        hc_fail;
reg        hc_use_to;
reg        no_host = 1'b0;
reg [27:0] hc_to;
reg  [2:0] wcnt;
reg [40:0] r_off;                 // byte offset of the request in the file
reg [14:0] r_len;                 // bytes of the request
reg [14:0] r_valid;               // bytes of it in the file
reg [14:0] idx;
reg [31:0] wacc;

wire [15:0] file_id = FILE_ID0 + {13'd0, slot};
wire [40:0] off_of  = {sd_lba[slot], 9'd0};
wire [14:0] len_of  = {sd_blk_cnt[slot] + 7'd1, 9'd0};
wire [41:0] room    = {1'b0, size[slot]} - {1'b0, off_of};   // bytes from the offset to the end

always @(posedge clk) begin
	img_mounted <= 7'd0;
	sd_buff_wr  <= 1'b0;
	b_we        <= 1'b0;
	if (flush_cnt != 28'd0) flush_cnt <= flush_cnt - 28'd1;

	if (reset) begin
		state       <= S_IDLE;
		ready       <= 1'b0;
		mounting    <= 1'b0;
		hc_request  <= 1'b0;
		sd_ack      <= 7'd0;
		dirty       <= 6'd0;
		dbg_mounted <= 6'd0;
		for (int i = 0; i < 7; i++) size[i] <= 41'd0;
	end
	else case (state)
	S_IDLE:
		if (start && !ready && !mounting) begin
			mounting <= 1'b1;
			slot     <= 3'd0;
			state    <= S_MOUNT;
		end
		else if (ready) begin
			// a request of the next slot in turn
			if ((sd_rd[rr] || sd_wr[rr]) && rr < 3'd7) begin
				slot  <= rr;
				state <= S_REQ;
			end
			else if (dirty != 6'd0 && flush_cnt == 28'd0) begin
				slot <= (dirty[0] ? 3'd0 : dirty[1] ? 3'd1 : dirty[2] ? 3'd2 : dirty[3] ? 3'd3 : dirty[4] ? 3'd4 : 3'd5);
				state <= S_FLUSH;
			end
			rr <= (rr == 3'd6) ? 3'd0 : rr + 3'd1;
		end

	// ---------------------------------------------- mounting
	S_MOUNT: begin
		hc_cmd    <= CMD_FILE_GET_SIZE;
		hc_p1     <= {16'd0, file_id};
		hc_p2     <= 32'd0; hc_p3 <= 32'd0; hc_p4 <= 32'd0; hc_p5 <= 32'd0;
		hc_use_to <= (slot == 3'd0);    // only the first command can show that there is no host
		ret       <= S_MOUNT2;
		state     <= no_host ? S_MOUNT2 : S_HC0;
		hc_fail   <= no_host;
	end
	S_MOUNT2: begin
		if (!hc_fail && hc_res0 == 32'd0 && (hc_res2[31:9] == 23'd0) && {hc_res2[8:0], hc_res1} >= 41'd512) begin
			size[slot]  <= {hc_res2[8:0], hc_res1};
			img_size    <= {23'd0, hc_res2[8:0], hc_res1};
			img_mounted[slot] <= 1'b1;
			dbg_mounted[slot] <= 1'b1;
		end
		state <= S_MOUNT3;
	end
	S_MOUNT3:
		// a few clocks between two slots' pulses
		if (slot == 3'd5) begin
			mounting <= 1'b0;
			ready    <= 1'b1;
			state    <= S_IDLE;
		end
		else begin
			slot  <= slot + 3'd1;
			state <= S_MOUNT;
		end

	// ---------------------------------------------- a request
	S_REQ: begin
		r_off   <= off_of;
		r_len   <= len_of;
		r_valid <= (size[slot] == 41'd0 || room[41] || room == 42'd0) ? 15'd0 :
		           (room >= {27'd0, len_of}) ? len_of : room[14:0];
		idx     <= 15'd0;
		if (sd_rd[slot]) state <= S_RD_CMD;
		else begin
			sd_ack[slot] <= 1'b1;
			state <= S_WR_ADDR;
		end
	end

	// read: FileRead into the buffer, then the bytes to the Falcon
	S_RD_CMD:
		if (r_valid == 15'd0) state <= S_RD_ACK;
		else begin
			hc_cmd <= CMD_FILE_READ;
			hc_p1  <= {16'd0, file_id};
			hc_p2  <= BUF_ADDR;
			hc_p3  <= r_off[31:0];
			hc_p4  <= {23'd0, r_off[40:32]};
			hc_p5  <= {17'd0, r_valid};
			hc_use_to <= 1'b0;
			ret    <= S_RD_WAIT;
			state  <= S_HC0;
		end
	S_RD_WAIT: begin
		// what the host did not read is 0
		if (hc_fail || hc_res0 != 32'd0) begin r_valid <= 15'd0; dbg_state[7] <= 1'b1; end
		else if (hc_res1 < {17'd0, r_valid}) r_valid <= hc_res1[14:0];
		state <= S_RD_ACK;
	end
	S_RD_ACK: begin
		sd_ack[slot] <= 1'b1;
		b_addr <= 12'd0;
		state  <= S_RD_ADDR;
	end
	S_RD_ADDR: state <= S_RD_BYTE;        // b_q follows b_addr
	S_RD_BYTE: begin
		sd_buff_addr <= idx[13:0];
		sd_buff_dout <= (idx < r_valid) ? b_q[8 * idx[1:0] +: 8] : 8'd0;
		sd_buff_wr   <= 1'b1;
		if (idx == r_len - 15'd1) begin
			dbg_read <= dbg_read + {17'd0, r_len[14:9]};
			state <= S_END;
		end
		else begin
			idx    <= idx + 15'd1;
			b_addr <= (idx + 15'd1) >> 2;
			state  <= S_RD_ADDR;
		end
	end

	// write: the bytes from the Falcon into the buffer, then FileWrite
	S_WR_ADDR: begin
		sd_buff_addr <= idx[13:0];
		wcnt  <= 3'd1;
		state <= S_WR_WAIT;
	end
	S_WR_WAIT:
		if (wcnt != 3'd0) wcnt <= wcnt - 3'd1;
		else state <= S_WR_BYTE;
	S_WR_BYTE: begin
		wacc[8 * idx[1:0] +: 8] <= sd_buff_din[slot];
		if (idx[1:0] == 2'd3) begin
			b_addr  <= idx[13:2];
			b_wdata <= {sd_buff_din[slot], wacc[23:0]};
			b_we    <= 1'b1;
		end
		if (idx == r_len - 15'd1) begin
			sd_ack[slot] <= 1'b0;
			state <= S_WR_CMD;
		end
		else begin
			idx   <= idx + 15'd1;
			state <= S_WR_ADDR;
		end
	end
	S_WR_CMD:
		if (r_valid == 15'd0) state <= S_DROP;
		else begin
			hc_cmd <= CMD_FILE_WRITE;
			hc_p1  <= {16'd0, file_id};
			hc_p2  <= BUF_ADDR;
			hc_p3  <= r_off[31:0];
			hc_p4  <= {23'd0, r_off[40:32]};
			hc_p5  <= {17'd0, r_valid};
			hc_use_to <= 1'b0;
			ret    <= S_DROP;
			state  <= S_HC0;
			dirty[slot] <= 1'b1;
			flush_cnt   <= FLUSH_TIME[27:0];
			dbg_written <= dbg_written + {17'd0, r_len[14:9]};
		end

	S_END: begin
		sd_ack[slot] <= 1'b0;
		state <= S_DROP;
	end
	// the request goes away
	S_DROP:
		if (!sd_rd[slot] && !sd_wr[slot]) state <= S_IDLE;

	S_FLUSH: begin
		dirty[slot] <= 1'b0;
		hc_cmd <= CMD_FILE_FLUSH;
		hc_p1  <= {16'd0, file_id};
		hc_p2  <= 32'd0; hc_p3 <= 32'd0; hc_p4 <= 32'd0; hc_p5 <= 32'd0;
		hc_use_to <= 1'b0;
		ret    <= S_IDLE;
		state  <= S_HC0;
	end

	// ---------------------------------------------- host command
	S_HC0: begin
		hc_request <= 1'b1;
		hc_to      <= 28'd0;
		state      <= S_HC1;
	end
	S_HC1:
		if (hc_done || hc_error) begin
			hc_fail    <= hc_error;
			hc_request <= 1'b0;
			wcnt       <= 3'd7;
			state      <= S_HC2;
		end
		else if (hc_use_to && hc_to == HOST_TIME) begin
			hc_fail    <= 1'b1;
			no_host    <= 1'b1;
			hc_request <= 1'b0;
			wcnt       <= 3'd7;
			state      <= S_HC2;
		end
		else hc_to <= hc_to + 28'd1;
	// the framework clears done / error once the request is low
	S_HC2:
		if (wcnt != 3'd0) wcnt <= wcnt - 3'd1;
		else if (!hc_done && !hc_error) state <= ret;

	default: state <= S_IDLE;
	endcase
	dbg_state[6:0] <= {slot, state[3:0]};
end

endmodule
