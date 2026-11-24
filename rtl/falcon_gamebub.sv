// Atari Falcon030 for the Game Bub.
//
// Top level bound by chisel/src/FalconCore.scala. It takes the place of
// Falcon.sv (the MiSTer "emu" module) of Falcon_MiSTer:
//
//   MiSTer                      Game Bub
//   ------                      --------
//   pll (32 MHz)                MMCM: 31.979 MHz system, 95.94 MHz memory
//   DDR3 (falcon_memarb)        gb_sdram: the first SDRAM chip
//   hps_io ioctl (TOS, cart)    gb_host: the files through falcon_system's
//                               loader
//   hps_io sd_* (Main_MiSTer)   gb_disk: the images on the microSD card, on
//                               demand
//   falcon_nvram_store          gb_host: the NVRAM file
//   ascal / video_mixer         gb_fb: the Falcon's own resolution in the
//                               SRAM and block RAM, scaled to the panel and
//                               HDMI
//   PS/2, joysticks             gb_input: Game Bub controllers, the dock's
//                               keyboard and mouse (firmware fork)
//   the 68882 on the ARM        none (F-line: no FPU, as on a Falcon
//                               without one)
//
// SDRAM chip 0 (32 MB): the Falcon's 16 MB guest space (ST-RAM, TOS at
// $E00000, the cartridge at $FA0000) in its first 16 MB. Chip 1: not used.
// SRAM: the picture (gb_fb).
//
// SPDX-License-Identifier: GPL-2.0-or-later

module falcon_gamebub
#(
	parameter int DISPLAY_DIVIDER = 35
)
(
	input  logic        clock,
	input  logic        reset,
	input  logic        clocks_clockIn50M,
	output logic        clocks_clockOutSystem,
	output logic        clocks_clockOutDisplay,
	output logic        clocks_clockOutSpi,
	output logic        clocks_locked,
	output logic        video_data_r,
	output logic        video_data_g,
	output logic        video_data_b,
	output logic        video_dataEnable,
	output logic        video_vblank,
	output logic        video_hblank,
	output logic        video_fit,
	input  logic        video_external_clock,
	input  logic        video_external_active,
	input  logic        video_external_hdmi,
	input  logic [10:0] video_external_x,
	input  logic [9:0]  video_external_y,
	input  logic        video_external_sync,
	input  logic        video_external_frame,
	output logic [23:0] video_external_color,
	output logic        video_external_enable,
	input  logic        video_frames_write,
	input  logic        video_frames_drop,
	output logic [15:0] audio_left,
	output logic [15:0] audio_right,
	input  logic        host_mem_enable,
	input  logic        host_mem_write,
	output logic        host_mem_done,
	input  logic [31:0] host_mem_address,
	output logic [31:0] host_mem_dataRead,
	input  logic [31:0] host_mem_dataWrite,
	input  logic        host_commandHost_request,
	output logic        host_commandHost_busy,
	output logic        host_commandHost_done,
	output logic        host_commandHost_error,
	output logic        host_commandCore_request,
	input  logic        host_commandCore_busy,
	input  logic        host_commandCore_done,
	input  logic        host_commandCore_error,
	input  logic        input_slots_0_active,
	input  logic [3:0]  input_slots_0_deviceType,
	input  logic        input_slots_0_buttons_a,
	input  logic        input_slots_0_buttons_b,
	input  logic        input_slots_0_buttons_x,
	input  logic        input_slots_0_buttons_y,
	input  logic        input_slots_0_buttons_up,
	input  logic        input_slots_0_buttons_down,
	input  logic        input_slots_0_buttons_left,
	input  logic        input_slots_0_buttons_right,
	input  logic        input_slots_0_buttons_l1,
	input  logic        input_slots_0_buttons_r1,
	input  logic        input_slots_0_buttons_l2,
	input  logic        input_slots_0_buttons_r2,
	input  logic        input_slots_0_buttons_l3,
	input  logic        input_slots_0_buttons_r3,
	input  logic        input_slots_0_buttons_start,
	input  logic        input_slots_0_buttons_select,
	input  logic signed [7:0] input_slots_0_analog_leftX,
	input  logic signed [7:0] input_slots_0_analog_leftY,
	input  logic signed [7:0] input_slots_0_analog_rightX,
	input  logic signed [7:0] input_slots_0_analog_rightY,
	input  logic [7:0]  input_slots_0_analog_leftTrigger,
	input  logic [7:0]  input_slots_0_analog_rightTrigger,
	input  logic        input_slots_1_active,
	input  logic [3:0]  input_slots_1_deviceType,
	input  logic        input_slots_1_buttons_a,
	input  logic        input_slots_1_buttons_b,
	input  logic        input_slots_1_buttons_x,
	input  logic        input_slots_1_buttons_y,
	input  logic        input_slots_1_buttons_up,
	input  logic        input_slots_1_buttons_down,
	input  logic        input_slots_1_buttons_left,
	input  logic        input_slots_1_buttons_right,
	input  logic        input_slots_1_buttons_l1,
	input  logic        input_slots_1_buttons_r1,
	input  logic        input_slots_1_buttons_l2,
	input  logic        input_slots_1_buttons_r2,
	input  logic        input_slots_1_buttons_l3,
	input  logic        input_slots_1_buttons_r3,
	input  logic        input_slots_1_buttons_start,
	input  logic        input_slots_1_buttons_select,
	input  logic signed [7:0] input_slots_1_analog_leftX,
	input  logic signed [7:0] input_slots_1_analog_leftY,
	input  logic signed [7:0] input_slots_1_analog_rightX,
	input  logic signed [7:0] input_slots_1_analog_rightY,
	input  logic [7:0]  input_slots_1_analog_leftTrigger,
	input  logic [7:0]  input_slots_1_analog_rightTrigger,
	output logic        sdram_clock,
	output logic [1:0]  sdram_cke,
	output logic [1:0]  sdram_cs,
	output logic        sdram_ras,
	output logic        sdram_cas,
	output logic        sdram_we,
	output logic [1:0]  sdram_dqm,
	output logic [1:0]  sdram_bank,
	output logic [12:0] sdram_address,
	input  logic [15:0] sdram_dataIn,
	output logic [15:0] sdram_dataOut,
	output logic        sdram_dataDir,
	output logic        sram_ceN,
	output logic        sram_weN,
	output logic        sram_oeN,
	output logic [1:0]  sram_writeMaskN,
	output logic [17:0] sram_address,
	input  logic [15:0] sram_dataIn,
	output logic [15:0] sram_dataOut,
	output logic        sram_dataDir
);

localparam int CLK_HZ = 31979167;

// ===========================================================================
// Clocks and resets
// ===========================================================================
wire clk_mem, clk_sys, clk_sdram, locked;

gb_clocks #(.DISPLAY_DIVIDER(DISPLAY_DIVIDER)) clocks
(
	.clk_in_50mhz (clocks_clockIn50M),
	.clk_mem      (clk_mem),
	.clk_sys      (clk_sys),
	.clk_sdram    (clk_sdram),
	.clk_display  (clocks_clockOutDisplay),
	.clk_spi      (clocks_clockOutSpi),
	.locked       (locked)
);
assign clocks_clockOutSystem = clk_sys;   // comes back as `clock`
assign clocks_locked         = locked;

// the framework's reset, synchronous to clk_sys (= clock)
reg [7:0] rst_sh = 8'hFF;
reg       reset_d = 1'b1;
always @(posedge clk_sys) begin
	rst_sh  <= {rst_sh[6:0], reset | ~locked};
	reset_d <= |rst_sh;
end
reg [1:0] rstm_sh = 2'b11;
wire      reset_mem = rstm_sh[1];
always @(posedge clk_mem) rstm_sh <= {rstm_sh[0], reset_d};

// power on: 256 clocks after the framework's reset
reg [7:0] por_cnt = 8'd0;
wire      por = ~&por_cnt;
always @(posedge clk_sys) begin
	if (reset_d) por_cnt <= 8'd0;
	else if (por) por_cnt <= por_cnt + 8'd1;
end

// ===========================================================================
// Host
// ===========================================================================
wire        core_reset, host_cold, tos_loaded, ram_tos, disk_start, disk_ready, focus;
wire  [1:0] set_monitor, mouse_speed;
wire        set_ram4, set_falcon_speed, sram_safe;
wire  [7:0] key_x, key_y, key_start, key_select;
wire        hmouse_valid, hkey_valid, hkey_down;
wire [15:0] hmouse_dx, hmouse_dy;
wire  [2:0] hmouse_btn;
wire  [7:0] hkey_usage;
wire [31:0] hc_cmd, hc_p1, hc_p2, hc_p3, hc_p4, hc_p5, hc_res0, hc_res1, hc_res2;
wire [11:0] hb_addr;
wire        hb_we;
wire [31:0] hb_wdata, hb_rdata;
wire        ld_wr, ld_busy;
wire [23:0] ld_addr;
wire  [7:0] ld_data;
wire        nv_init, nv_ready, nv_wr;
wire  [5:0] nv_addr;
wire  [7:0] nv_din, nv_dout;
wire [31:0] dbg_read, dbg_written, dbg_geom, dbg_sdram_cmds;
wire  [7:0] dbg_dstate;
wire  [5:0] dbg_mounted;
wire [15:0] dbg_lines, dbg_late;
wire        dbg_overflow;
wire        falcon_reset;

gb_host host
(
	.clk(clk_sys), .reset(reset_d),
	.mem_address(host_mem_address), .mem_enable(host_mem_enable), .mem_write(host_mem_write),
	.mem_dataRead(host_mem_dataRead), .mem_dataWrite(host_mem_dataWrite), .mem_done(host_mem_done),
	.cmd_request(host_commandHost_request), .cmd_busy(host_commandHost_busy),
	.cmd_done(host_commandHost_done), .cmd_error(host_commandHost_error),
	.ld_wr(ld_wr), .ld_addr(ld_addr), .ld_data(ld_data), .ld_busy(ld_busy),
	.nv_init(nv_init), .nv_ready(nv_ready), .nv_addr(nv_addr), .nv_din(nv_din), .nv_wr(nv_wr), .nv_dout(nv_dout),
	.core_reset(core_reset), .cold_reset(host_cold), .tos_loaded(tos_loaded), .ram_tos(ram_tos),
	.disk_start(disk_start), .disk_ready(disk_ready), .focus(focus),
	.set_monitor(set_monitor), .set_ram4(set_ram4), .set_falcon_speed(set_falcon_speed),
	.key_x(key_x), .key_y(key_y), .key_start(key_start), .key_select(key_select),
	.sram_safe(sram_safe), .mouse_speed(mouse_speed),
	.hmouse_valid(hmouse_valid), .hmouse_dx(hmouse_dx), .hmouse_dy(hmouse_dy), .hmouse_btn(hmouse_btn),
	.hkey_valid(hkey_valid), .hkey_usage(hkey_usage), .hkey_down(hkey_down),
	.hc_cmd(hc_cmd), .hc_p1(hc_p1), .hc_p2(hc_p2), .hc_p3(hc_p3), .hc_p4(hc_p4), .hc_p5(hc_p5),
	.hc_res0(hc_res0), .hc_res1(hc_res1), .hc_res2(hc_res2),
	.hb_addr(hb_addr), .hb_we(hb_we), .hb_wdata(hb_wdata), .hb_rdata(hb_rdata),
	.stat_run(!falcon_reset), .stat_stall(falcon_reset),
	.dbg_read(dbg_read), .dbg_written(dbg_written),
	.dbg_disk({16'd0, 2'd0, dbg_mounted, dbg_dstate}), .dbg_geom(dbg_geom),
	.dbg_fb({dbg_overflow, dbg_late[14:0], dbg_lines}), .dbg_sdram(dbg_sdram_cmds)
);

// the Falcon's resets: a cold reset (power on, TOS loaded, the Cold reset
// setting) also clears TOS's warm start flag; the settings that select the
// machine are taken while it is in reset
reg  [7:0] cold_cnt = 8'd0;
always @(posedge clk_sys) begin
	if (por || host_cold) cold_cnt <= 8'hFF;
	else if (cold_cnt != 8'd0) cold_cnt <= cold_cnt - 8'd1;
end
wire cold_reset = por || cold_cnt != 8'd0;
assign falcon_reset = reset_d || por || core_reset || cold_reset;

reg  [1:0] m_monitor = 2'b10;
reg        m_ram4 = 1'b0;
always @(posedge clk_sys) if (falcon_reset) begin
	// falcon_system's encoding: 10 VGA, 01 RGB, 11 TV, 00 mono
	m_monitor <= (set_monitor == 2'd0) ? 2'b10 : (set_monitor == 2'd1) ? 2'b01 :
	             (set_monitor == 2'd2) ? 2'b11 : 2'b00;
	m_ram4    <= set_ram4;
end

// ===========================================================================
// Input
// ===========================================================================
wire [31:0] joy0, joy1;
wire [24:0] ps2_mouse;
wire [10:0] ps2_key;

gb_input #(.CLK_HZ(CLK_HZ)) inp
(
	.clk(clk_sys), .reset(reset_d),
	.btn_a(input_slots_0_buttons_a), .btn_b(input_slots_0_buttons_b),
	.btn_x(input_slots_0_buttons_x), .btn_y(input_slots_0_buttons_y),
	.btn_up(input_slots_0_buttons_up), .btn_down(input_slots_0_buttons_down),
	.btn_left(input_slots_0_buttons_left), .btn_right(input_slots_0_buttons_right),
	.btn_l(input_slots_0_buttons_l1), .btn_r(input_slots_0_buttons_r1),
	.btn_start(input_slots_0_buttons_start), .btn_select(input_slots_0_buttons_select),
	.stick_lx(input_slots_0_analog_leftX), .stick_ly(input_slots_0_analog_leftY),
	.stick_rx(input_slots_0_analog_rightX), .stick_ry(input_slots_0_analog_rightY),
	.p1_active(input_slots_1_active), .p1_a(input_slots_1_buttons_a),
	.p1_up(input_slots_1_buttons_up), .p1_down(input_slots_1_buttons_down),
	.p1_left(input_slots_1_buttons_left), .p1_right(input_slots_1_buttons_right),
	.p1_lx(input_slots_1_analog_leftX), .p1_ly(input_slots_1_analog_leftY),
	.key_x(key_x), .key_y(key_y), .key_start(key_start), .key_select(key_select),
	.mouse_speed(mouse_speed),
	.hmouse_valid(hmouse_valid), .hmouse_dx(hmouse_dx), .hmouse_dy(hmouse_dy), .hmouse_btn(hmouse_btn),
	.hkey_valid(hkey_valid), .hkey_usage(hkey_usage), .hkey_down(hkey_down),
	.joy0(joy0), .joy1(joy1), .ps2_mouse(ps2_mouse), .ps2_key(ps2_key)
);

// ===========================================================================
// The Falcon
// ===========================================================================
wire  [6:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba [7];
wire  [6:0] sd_rd, sd_wr, sd_ack;
wire  [5:0] sd_blk_cnt [7];
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din [7];
wire        sd_buff_wr;

wire  [7:0] r, g, b;
wire        hs, vs, hblank, vblank, ce_pix, vid_de, vid_de_tb, vid_field, vid_lace;
wire signed [15:0] audio_l, audio_r;

wire        ddr_busy, ddr_rd, ddr_we, ddr_ready;
wire  [7:0] ddr_burstcnt, ddr_be;
wire [28:0] ddr_addr;
wire [63:0] ddr_dout, ddr_din;

falcon_system #(.CLK_HZ(CLK_HZ), .TT(0)) system
(
	.clk(clk_sys), .clk_cpu(clk_sys),
	.reset(falcon_reset), .cold_reset(cold_reset), .por(por),
	.ram_mb(m_ram4 ? 4'd4 : 4'd14), .ram_tos(ram_tos), .fast_ram(2'd0),
	.monitor(m_monitor), .cpu_turbo(!set_falcon_speed),
	.tt_mode(1'b0), .ttram_sel(2'd0), .tstat_en(1'b0), .net_on(1'b0), .fpu_ok(), .vme_sel(2'd0),
	.ld_wr(ld_wr), .ld_addr(ld_addr), .ld_data(ld_data), .ld_busy(ld_busy),
	.ps2_key(ps2_key), .ps2_mouse(ps2_mouse), .joy0(joy0), .joy1(joy1), .ana0(16'd0), .ana1(16'd0),
	.rtc(65'd0),
	.nv_init(nv_init), .nv_addr(nv_addr), .nv_din(nv_din), .nv_wr(nv_wr), .nv_dout(nv_dout),
	.nv_changed(), .nv_ready(nv_ready),
	.img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
	.sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_blk_cnt(sd_blk_cnt), .sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
	.r(r), .g(g), .b(b), .hsync(hs), .vsync(vs), .hblank(hblank), .vblank(vblank), .ce_pix(ce_pix),
	.vid_de(vid_de), .vid_de_tb(vid_de_tb), .vid_field(vid_field), .vid_lace(vid_lace),
	.fb_en(), .fb_format(), .fb_width(), .fb_height(), .fb_base(), .fb_stride(),
	.fb_pal_wr(), .fb_pal_addr(), .fb_pal_rgb(),
	.mic_l(16'sd0), .mic_r(16'sd0), .audio_l(audio_l), .audio_r(audio_r),
	.midi_rx(1'b1), .midi_tx(), .ser_rx(1'b1), .ser_tx(), .ser_hs(1'b0), .ser_port(1'b0),
	.ser_cts(1'b0), .ser_rts(),
	.fdd_led(), .hdd_led(),
	.DDRAM_BUSY(ddr_busy), .DDRAM_BURSTCNT(ddr_burstcnt), .DDRAM_ADDR(ddr_addr),
	.DDRAM_DOUT(ddr_dout), .DDRAM_DOUT_READY(ddr_ready), .DDRAM_RD(ddr_rd),
	.DDRAM_DIN(ddr_din), .DDRAM_BE(ddr_be), .DDRAM_WE(ddr_we)
);

assign audio_left  = audio_l;
assign audio_right = audio_r;

// ===========================================================================
// Memory
// ===========================================================================
gb_sdram ram
(
	.clk_sys(clk_sys),
	.DDRAM_BUSY(ddr_busy), .DDRAM_BURSTCNT(ddr_burstcnt), .DDRAM_ADDR(ddr_addr),
	.DDRAM_DOUT(ddr_dout), .DDRAM_DOUT_READY(ddr_ready), .DDRAM_RD(ddr_rd),
	.DDRAM_DIN(ddr_din), .DDRAM_BE(ddr_be), .DDRAM_WE(ddr_we),
	.clk_mem(clk_mem), .clk_sdram(clk_sdram), .reset_mem(reset_mem),
	.sd_clk(sdram_clock), .sd_cke(sdram_cke), .sd_cs(sdram_cs), .sd_ras(sdram_ras), .sd_cas(sdram_cas),
	.sd_we(sdram_we), .sd_dqm(sdram_dqm), .sd_ba(sdram_bank), .sd_addr(sdram_address),
	.sd_data_in(sdram_dataIn), .sd_data_out(sdram_dataOut), .sd_data_oe(sdram_dataDir),
	.init_done(), .dbg_cmds(dbg_sdram_cmds)
);

// ===========================================================================
// Disks
// ===========================================================================
gb_disk #(.CLK_HZ(CLK_HZ)) disk
(
	.clk(clk_sys), .reset(reset_d), .start(disk_start), .ready(disk_ready),
	.img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
	.sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_blk_cnt(sd_blk_cnt), .sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
	.hc_request(host_commandCore_request), .hc_cmd(hc_cmd),
	.hc_p1(hc_p1), .hc_p2(hc_p2), .hc_p3(hc_p3), .hc_p4(hc_p4), .hc_p5(hc_p5),
	.hc_done(host_commandCore_done), .hc_error(host_commandCore_error),
	.hc_res0(hc_res0), .hc_res1(hc_res1), .hc_res2(hc_res2),
	.hb_addr(hb_addr), .hb_we(hb_we), .hb_wdata(hb_wdata), .hb_rdata(hb_rdata),
	.dbg_read(dbg_read), .dbg_written(dbg_written), .dbg_mounted(dbg_mounted), .dbg_state(dbg_dstate)
);

// ===========================================================================
// Video
// ===========================================================================
gb_fb fb
(
	.clk_sys(clk_sys), .reset(reset_d),
	.ce_pix(ce_pix), .de_tb(vid_de_tb), .vblank(vblank), .field(vid_field), .lace(vid_lace),
	.r(r), .g(g), .b(b),
	.wr_frame(video_frames_write), .wr_drop(video_frames_drop),
	.fw_de(video_dataEnable), .fw_hblank(video_hblank), .fw_vblank(video_vblank),
	.clk_mem(clk_mem), .reset_mem(reset_mem), .sram_safe(sram_safe),
	.sram_ceN(sram_ceN), .sram_weN(sram_weN), .sram_oeN(sram_oeN), .sram_writeMaskN(sram_writeMaskN),
	.sram_address(sram_address), .sram_dataIn(sram_dataIn), .sram_dataOut(sram_dataOut),
	.sram_dataDir(sram_dataDir),
	.clk_av(video_external_clock), .av_hdmi(video_external_hdmi), .av_sync(video_external_sync),
	.av_frame(video_external_frame), .av_x(video_external_x), .av_y(video_external_y),
	.av_color(video_external_color),
	.dbg_geom(dbg_geom), .dbg_lines(dbg_lines), .dbg_late(dbg_late), .dbg_overflow(dbg_overflow)
);

assign video_external_enable = 1'b1;
assign video_data_r = 1'b0;
assign video_data_g = 1'b0;
assign video_data_b = 1'b0;
assign video_fit    = 1'b0;

endmodule
