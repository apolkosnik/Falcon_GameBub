// Full-system bench of the Game Bub Falcon core (tb_top.sv): plays the Game
// Bub around falcon_gamebub.
//
//   - The firmware's load sequence, as firmware/handheld/src/core does it:
//     the files in files.json order (FileWriteStart, the data as 32-bit words
//     with file byte 0 in bits 7:0, FileWriteEnd with the size; a missing
//     optional file with "initialize" as 0xFF words), the settings, then
//     SetupComplete and CoreRun. On-demand files (the disks) are opened, not
//     loaded.
//   - The firmware's worker loop: a core request (host_commandCore_request)
//     is read at 0xF000_1000..14 and served on the image files: FileGetSize,
//     FileRead (the bytes written into the core's buffer), FileWrite (read
//     from it), FileFlush; the results go to 0xF000_1000..08, then done until
//     the request goes low.
//   - The framework's frames (HandheldTop.scala with ownFrames): which frame
//     is written, thrown away, completed, shown on the panel.
//   - The panel scanned as its driver does (rev 4: 800 columns of 480 rows,
//     the core's 720 at x = column - 12), or HDMI's 1280 x 720, through the
//     external picture: every colour taken 12 clocks after its pixel is named.
//
// Options:
//   --tos FILE          TOS image (files.json id 0), required
//   --fda/--fdb FILE    floppy images (ids 1, 2)    --ide0/--ide1 FILE (3, 4)
//   --scsi0/--scsi1 FILE (5, 6)                     --nvram FILE (7)
//   --ms N              simulated milliseconds (default 3000)
//   --set A=V           a setting (hex address, hex value) before the start
//   --frames DIR        Videl's frames as DIR/frame_NNNN.ppm (--every N: every Nth)
//   --screens DIR       the panel (or --hdmi: HDMI) as the core shows it,
//                       DIR/screen_NNNN.ppm, every --screen-every N screen frames
//   --hdmi              scan HDMI instead of the panel
//   --key T:U[:D]       at T ms press USB HID usage U (hex) on the dock keyboard
//                       for D ms (default 100)
//   --button T:B[:D]    at T ms hold button B (0 a, 1 b, 2 x, 3 y, 4 up, 5 down,
//                       6 left, 7 right, 8 l, 9 r, 10 start, 11 select) for D ms
//   --mouse T:DX:DY:B   at T ms a dock mouse report
//   --pc-every N        print the CPU's PC every N ms
//   --text ADDR         print the NUL-terminated text at guest ADDR at the end
//   --peek ADDR         print the long word at guest ADDR at the end
//   --expect-screen H   fail unless the last screen's checksum is H (hex)
//   --check-screen      the last screen must be Videl's last (or the one
//                       before) frame as gb_fb scales it
//   --write-back        write the disks' changes into the image files (default:
//                       to the bench's copy in memory only)
// The run fails on any SDRAM or SRAM model error.
//
// SPDX-License-Identifier: GPL-2.0-or-later
#include "Vtb_top.h"
#include "verilated.h"
#include "svdpi.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <deque>
#include <functional>

extern "C" unsigned guest_peek8(unsigned a);

static Vtb_top *top;
static uint64_t half = 0;              // half periods of clk_mem
static const double T_MEM = 10.424e-9; // clk_mem period
static double now_ms() { return half * T_MEM / 2 * 1e3; }

// ------------------------------------------------------------- files
struct Image {
	std::string path;
	std::vector<uint8_t> data;
	bool present = false;
	bool dirty = false;
};
static Image files[9];
static bool write_back = false;

static bool load(Image &im, const char *path) {
	FILE *f = fopen(path, "rb");
	if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
	fseek(f, 0, SEEK_END);
	im.data.resize(ftell(f));
	fseek(f, 0, SEEK_SET);
	if (fread(im.data.data(), 1, im.data.size(), f) != im.data.size()) { fprintf(stderr, "read %s\n", path); exit(1); }
	fclose(f);
	im.path = path;
	im.present = true;
	return true;
}

// ------------------------------------------------------------- host operations
// executed one after the other on clk_sys edges
struct Op {
	enum Kind { W, R, CMD, CORE_DONE, CALL } kind;
	uint32_t addr = 0, data = 0;
	uint32_t *dst = nullptr;
	uint32_t cmd[4] = {0, 0, 0, 0};
	std::function<void()> fn;
};
static std::deque<Op> ops;
static int op_phase = 0;
static uint32_t cmd_result = 0;
static bool cmd_failed = false;

static void w(uint32_t a, uint32_t d) { Op o; o.kind = Op::W; o.addr = a; o.data = d; ops.push_back(o); }
static void r(uint32_t a, uint32_t *dst) { Op o; o.kind = Op::R; o.addr = a; o.dst = dst; ops.push_back(o); }
static void cmd(uint32_t c, uint32_t p1 = 0, uint32_t p2 = 0, uint32_t p3 = 0) {
	Op o; o.kind = Op::CMD; o.cmd[0] = c; o.cmd[1] = p1; o.cmd[2] = p2; o.cmd[3] = p3; ops.push_back(o);
}
static void call(std::function<void()> fn) { Op o; o.kind = Op::CALL; o.fn = fn; ops.push_back(o); }

enum { CMD_FILE_WR_START = 0x300, CMD_FILE_WR_END = 0x301, CMD_FILE_RD_START = 0x302, CMD_FILE_RD_END = 0x303,
       CMD_CORE_RUN = 0x100, CMD_CORE_HALT = 0x101, CMD_SETUP_COMPLETE = 0x102 };

// one step of the operation at the head, at a clk_sys edge (after it)
static void host_step() {
	if (ops.empty()) { top->host_mem_enable = 0; return; }
	Op &o = ops.front();
	switch (o.kind) {
	case Op::W: case Op::R:
		if (op_phase == 0) {
			top->host_mem_enable = 1; top->host_mem_write = (o.kind == Op::W);
			top->host_mem_address = o.addr; top->host_mem_dataWrite = o.data;
			op_phase = 1;
		} else if (top->host_mem_done) {
			if (o.kind == Op::R && o.dst) *o.dst = top->host_mem_dataRead;
			top->host_mem_enable = 0;
			op_phase = 0; ops.pop_front();
		}
		break;
	case Op::CMD:
		// parameters at 0xF000_0000..0C, then the request until done or error
		if (op_phase < 4) {
			if (op_phase % 1 == 0 && !top->host_mem_enable) {
				top->host_mem_enable = 1; top->host_mem_write = 1;
				top->host_mem_address = 0xF0000000 + 4 * op_phase; top->host_mem_dataWrite = o.cmd[op_phase];
			} else if (top->host_mem_done) { top->host_mem_enable = 0; op_phase++; }
		} else if (op_phase == 4) { top->host_cmd_request = 1; op_phase = 5; }
		else if (op_phase == 5) {
			if (top->host_cmd_done || top->host_cmd_error) {
				cmd_failed = top->host_cmd_error;
				op_phase = 6;
				top->host_mem_enable = 1; top->host_mem_write = 0; top->host_mem_address = 0xF0000000;
			}
		} else if (op_phase == 6) {
			if (top->host_mem_done) {
				cmd_result = top->host_mem_dataRead;
				top->host_mem_enable = 0; top->host_cmd_request = 0; op_phase = 7;
			}
		} else if (!top->host_cmd_busy && !top->host_cmd_done && !top->host_cmd_error) {
			if (cmd_failed) printf("[%9.3f ms] host: command %03x failed\n", now_ms(), o.cmd[0]);
			op_phase = 0; ops.pop_front();
		}
		break;
	case Op::CORE_DONE:
		if (op_phase == 0) { top->host_core_done = 1; op_phase = 1; }
		else if (!top->host_core_request) { top->host_core_done = 0; op_phase = 0; ops.pop_front(); }
		break;
	case Op::CALL: {
		auto fn = o.fn; ops.pop_front(); op_phase = 0;
		fn();
		break;
	}
	}
}

// the core's requests
static uint32_t creq[6];
static bool serving = false;
static long n_reads = 0, n_writes = 0;
static bool verbose_io = false;
static void serve() {
	uint32_t c = creq[0], id = creq[1], buf = creq[2];
	uint64_t off = (uint64_t)creq[4] << 32 | creq[3];
	uint32_t len = creq[5];
	Image *im = (id < 9) ? &files[id] : nullptr;
	std::deque<Op> mine;
	auto push_res = [&](uint32_t r0, uint32_t r1, uint32_t r2) {
		Op o; o.kind = Op::W;
		o.addr = 0xF0001000; o.data = r0; mine.push_back(o);
		o.addr = 0xF0001004; o.data = r1; mine.push_back(o);
		o.addr = 0xF0001008; o.data = r2; mine.push_back(o);
		Op d; d.kind = Op::CORE_DONE; mine.push_back(d);
	};
	if (verbose_io) printf("[%9.3f ms] core: cmd %03x file %u off %llu len %u\n", now_ms(), c, id, (unsigned long long)off, len);
	if (c == 0x400) {   // FileGetSize
		if (im && im->present) push_res(0, (uint32_t)im->data.size(), (uint32_t)((uint64_t)im->data.size() >> 32));
		else push_res(1, 0, 0);
	} else if (c == 0x402) {   // FileRead
		if (!im || !im->present) push_res(1, 0, 0);
		else {
			uint32_t n = 0;
			if (off < im->data.size()) n = (uint32_t)std::min<uint64_t>(len, im->data.size() - off);
			for (uint32_t i = 0; i < (n + 3) / 4; i++) {
				uint32_t v = 0;
				for (int k = 0; k < 4; k++) if (4 * i + k < n) v |= (uint32_t)im->data[off + 4 * i + k] << (8 * k);
				Op o; o.kind = Op::W; o.addr = buf + 4 * i; o.data = v; mine.push_back(o);
			}
			push_res(0, n, 0);
			n_reads++;
		}
	} else if (c == 0x403) {   // FileWrite
		if (!im || !im->present) push_res(1, 0, 0);
		else {
			static uint32_t wbuf[4096];
			for (uint32_t i = 0; i < (len + 3) / 4 && i < 4096; i++) {
				Op o; o.kind = Op::R; o.addr = buf + 4 * i; o.dst = &wbuf[i]; mine.push_back(o);
			}
			Op cl; cl.kind = Op::CALL;
			cl.fn = [im, off, len]() {
				for (uint32_t i = 0; i < len && off + i < im->data.size(); i++)
					im->data[off + i] = (uint8_t)(wbuf[i / 4] >> (8 * (i & 3)));
				im->dirty = true;
			};
			mine.push_back(cl);
			push_res(0, len, 0);
			n_writes++;
		}
	} else if (c == 0x404) push_res(0, 0, 0);   // FileFlush
	else push_res(1, 0, 0);
	Op e; e.kind = Op::CALL; e.fn = []() { serving = false; }; mine.push_back(e);
	for (auto it = mine.rbegin(); it != mine.rend(); ++it) ops.push_front(*it);
}

// ------------------------------------------------------------- pictures
static void write_ppm(const char *path, int w, int h, const std::vector<uint32_t> &px) {
	FILE *f = fopen(path, "wb");
	if (!f) return;
	fprintf(f, "P6\n%d %d\n255\n", w, h);
	for (uint32_t p : px) { uint8_t c[3] = {(uint8_t)(p >> 16), (uint8_t)(p >> 8), (uint8_t)p}; fwrite(c, 1, 3, f); }
	fclose(f);
}
static uint32_t checksum(const std::vector<uint32_t> &px) {
	uint32_t h = 2166136261u;
	for (uint32_t p : px) { h ^= p; h *= 16777619u; }
	return h;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	double run_ms = 3000;
	const char *frames_dir = nullptr, *screens_dir = nullptr;
	int every = 1, screen_every = 1;
	bool hdmi = false;
	double pc_every = 0;
	std::vector<std::pair<uint32_t, uint32_t>> sets;
	struct Ev { double t; int kind; int a, b, c; };
	std::vector<Ev> evs;
	std::vector<uint32_t> texts, peeks;
	long expect_screen = -1;
	bool check_screen = false;
	const char *fname[9] = {"--tos", "--fda", "--fdb", "--ide0", "--ide1", "--scsi0", "--scsi1", "--nvram", "--cart"};
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		bool more = i + 1 < argc;
		bool taken = false;
		for (int k = 0; k < 9; k++) if (a == fname[k] && more) { load(files[k], argv[++i]); taken = true; }
		if (taken) continue;
		if (a == "--ms" && more) run_ms = atof(argv[++i]);
		else if (a == "--frames" && more) frames_dir = argv[++i];
		else if (a == "--every" && more) every = atoi(argv[++i]);
		else if (a == "--screens" && more) screens_dir = argv[++i];
		else if (a == "--screen-every" && more) screen_every = atoi(argv[++i]);
		else if (a == "--hdmi") hdmi = true;
		else if (a == "--set" && more) { uint32_t ad, v; sscanf(argv[++i], "%x=%x", &ad, &v); sets.push_back({ad, v}); }
		else if (a == "--key" && more) { Ev e{}; int d = 100; sscanf(argv[++i], "%lf:%x:%d", &e.t, &e.a, &d); e.kind = 0; e.b = d; evs.push_back(e); }
		else if (a == "--button" && more) { Ev e{}; int d = 100; sscanf(argv[++i], "%lf:%d:%d", &e.t, &e.a, &d); e.kind = 1; e.b = d; evs.push_back(e); }
		else if (a == "--mouse" && more) { Ev e{}; sscanf(argv[++i], "%lf:%d:%d:%d", &e.t, &e.a, &e.b, &e.c); e.kind = 2; evs.push_back(e); }
		else if (a == "--pc-every" && more) pc_every = atof(argv[++i]);
		else if (a == "--text" && more) texts.push_back(strtoul(argv[++i], nullptr, 16));
		else if (a == "--peek" && more) peeks.push_back(strtoul(argv[++i], nullptr, 16));
		else if (a == "--expect-screen" && more) expect_screen = strtol(argv[++i], nullptr, 16);
		else if (a == "--write-back") write_back = true;
		else if (a == "--check-screen") check_screen = true;
		else if (a == "--verbose-io") verbose_io = true;
		else if (a[0] == '+') ;
		else { fprintf(stderr, "unknown option %s\n", a.c_str()); return 1; }
	}
	if (!files[0].present) { fprintf(stderr, "--tos FILE is required\n"); return 1; }

	top = new Vtb_top;
	top->mmcm_locked = 1;
	top->reset = 1;
	top->av_hdmi = hdmi;

	// ---- the load sequence
	for (int id = 0; id < 9; id++) {
		if (id >= 1 && id <= 6) continue;          // on demand: opened, not loaded
		uint32_t base = id == 0 ? 0x20000000 : id == 7 ? 0x40000000 : 0x21000000;
		Image &im = files[id];
		if (!im.present) {
			if (id == 7) for (int k = 0; k < 13; k++) w(base + 4 * k, 0xFFFFFFFF);   // "initialize"
			continue;
		}
		cmd(CMD_FILE_WR_START, id);
		for (size_t k = 0; k < (im.data.size() + 3) / 4; k++) {
			uint32_t v = 0;
			for (int b = 0; b < 4; b++) if (4 * k + b < im.data.size()) v |= (uint32_t)im.data[4 * k + b] << (8 * b);
			w(base + 4 * k, v);
		}
		cmd(CMD_FILE_WR_END, id, (uint32_t)im.data.size());
	}
	for (auto &s : sets) w(s.first, s.second);
	cmd(CMD_SETUP_COMPLETE);
	cmd(CMD_CORE_RUN);
	call([]() { printf("[%9.3f ms] host: CoreRun\n", now_ms()); });

	// ---- frames (the framework's choice), Videl's stream, the screen
	int wr_index = 1, last_complete = 0, shown = 0;
	bool started = false, drop_r = false, fwv_d = true;
	std::vector<uint32_t> vf(1024 * 1024);
	int vx = 0, vy = 0, vw = 0, vframe = 0;
	std::vector<uint32_t> last_frame, prev_frame;
	int last_w = 0, last_h = 0, prev_w = 0, prev_h = 0;
	bool vde_d = false, vvb_d = true;
	int scr_n = 0;
	const int SW = hdmi ? 1280 : 720, SH = hdmi ? 720 : 480;
	std::vector<uint32_t> screen(SW * SH);
	uint32_t last_screen_sum = 0;
	// the screen scan: panel 10 + 800 columns of 504 clocks, HDMI 750 lines of 1650
	long av_t = 0;
	const long av_line = hdmi ? 1650 : 504, av_lines = hdmi ? 750 : 810;
	struct Named { int x, y; bool v; };
	Named hist[13] = {};

	double next_pc = pc_every;
	uint64_t stop_half = (uint64_t)(run_ms * 1e-3 / (T_MEM / 2));
	uint32_t buttons = 0;
	std::vector<std::pair<double, uint32_t>> releases;
	bool core_req_d = false;

	for (half = 0; half < stop_half && !Verilated::gotFinish(); half++) {
		// clk_mem: high in even half periods; clk_sys: 6 half periods, high in
		// the first 3 (rising with every third clk_mem rising edge);
		// clk_av: panel ~24 MHz (8 half periods), HDMI ~72 MHz (rising with
		// every clk_mem edge, both edges: 2 half periods... 96 MHz/1.33 is not
		// modelled: it runs at 96 MHz, faster than HDMI's 74.25 MHz)
		int ph6 = half % 6;
		bool sys_rise = (ph6 == 0);
		top->clk_mem = !(half & 1);
		top->clk_sys = ph6 < 3;
		bool av_rise;
		if (hdmi) { top->clk_av = !(half & 1); av_rise = !(half & 1); }
		else { top->clk_av = (half % 8) < 4; av_rise = (half % 8) == 0; }
		if (half < 600) top->reset = 1; else top->reset = 0;
		top->eval();

		if (av_rise) {
			// what was named 12 clocks ago comes out now
			Named &h = hist[12];
			if (h.v && h.x >= 0 && h.x < SW && h.y >= 0 && h.y < SH) screen[h.y * SW + h.x] = top->av_color;
			for (int k = 12; k > 0; k--) hist[k] = hist[k - 1];
			long line = av_t / av_line, pos = av_t % av_line;
			Named n{-1, -1, false};
			if (!hdmi) {
				// columns 0..9 blank (sync), then the panel's 800 columns
				top->av_sync = (line < 1);
				if (line == 0 && pos == 0) { top->av_frame = last_complete; shown = last_complete; }
				if (line >= 10 && pos < 480) {
					int col = (int)line - 10;
					top->av_x = (col - 12) & 0x7FF;
					top->av_y = (int)pos;
					n = {col - 12, (int)pos, col >= 12 && col < 12 + 720};
				} else { top->av_x = 0x7FF; top->av_y = 500; }
			} else {
				// HDMI: line 720 starts the blank (sync), lines 0..719 the picture
				long y = (line + 720) % 750;
				top->av_sync = (y == 720);
				if (y == 720 && pos == 0) top->av_frame = last_complete;
				top->av_x = (int)pos; top->av_y = (int)y;
				n = {(int)pos, (int)y, y < 720 && pos < 1280};
			}
			hist[0] = n;
			av_t++;
			if (av_t == av_line * av_lines) {
				av_t = 0;
				scr_n++;
				last_screen_sum = checksum(screen);
				if (screens_dir && scr_n % screen_every == 0) {
					char p[512]; snprintf(p, sizeof p, "%s/screen_%04d.ppm", screens_dir, scr_n);
					write_ppm(p, SW, SH, screen);
				}
			}
		}

		if (!sys_rise) continue;

		// ---- the framework's frames (as HandheldTop)
		bool fwv = top->video_vblank;
		bool conflict = !hdmi && (wr_index == shown);
		bool drop = started ? drop_r : conflict;
		if (!fwv && top->video_de && !started) { started = true; drop_r = conflict; }
		if (fwv && !fwv_d) {
			if (!drop_r && started) { last_complete = wr_index; wr_index ^= 1; }
			started = false; drop_r = false;
			drop = conflict;
		}
		fwv_d = fwv;
		top->frames_write = wr_index;
		top->frames_drop = drop;

		// ---- Videl's frames
		if (top->vid_ce && top->vid_de_tb && !top->vid_vblank) {
			if (vx < 1024 && vy < 1024) vf[vy * 1024 + vx] = top->vid_r << 16 | top->vid_g << 8 | top->vid_b;
			vx++;
		}
		if (vde_d && !top->vid_de_tb && vx) { if (vx > vw) vw = vx; vx = 0; vy++; }
		vde_d = top->vid_de_tb;
		if (top->vid_vblank && !vvb_d) {
			if (vy) {
				prev_frame = last_frame; prev_w = last_w; prev_h = last_h;
				last_frame.assign(vw * vy, 0);
				for (int y = 0; y < vy; y++) for (int x = 0; x < vw; x++) last_frame[y * vw + x] = vf[y * 1024 + x];
				last_w = vw; last_h = vy;
			}
			if (vy && frames_dir && vframe % every == 0) {
				std::vector<uint32_t> out(vw * vy);
				for (int y = 0; y < vy; y++) for (int x = 0; x < vw; x++) out[y * vw + x] = vf[y * 1024 + x];
				char p[512]; snprintf(p, sizeof p, "%s/frame_%04d.ppm", frames_dir, vframe);
				write_ppm(p, vw, vy, out);
			}
			if (vy) vframe++;
			vx = 0; vy = 0; vw = 0;
		}
		vvb_d = top->vid_vblank;

		// ---- input events
		double t = now_ms();
		std::vector<Ev> later;
		for (auto &e : evs) if (e.t >= 0 && t >= e.t) {
			if (e.kind == 0) {
				uint32_t u = e.a;
				w(0x00001038, 0x100 | u);
				later.push_back(Ev{t + e.b, 3, (int)u, 0, 0});
				printf("[%9.3f ms] key %02x down\n", t, u);
			} else if (e.kind == 3) {
				w(0x00001038, (uint32_t)e.a);
			} else if (e.kind == 1) {
				buttons |= 1u << e.a;
				releases.push_back({t + e.b, 1u << e.a});
			} else if (e.kind == 2) {
				w(0x00001030, (uint32_t)(e.b & 0xFFFF) << 16 | (e.a & 0xFFFF));
				w(0x00001034, (uint32_t)e.c);
			}
			e.t = -1;
			break;
		}
		for (auto &e : later) evs.push_back(e);
		for (auto &rl : releases) if (rl.first >= 0 && t >= rl.first) { buttons &= ~rl.second; rl.first = -1; }
		top->buttons = buttons;

		// ---- the host
		bool creq_now = top->host_core_request;
		if (creq_now && !core_req_d && !serving) {
			serving = true;
			std::deque<Op> mine;
			for (int k = 0; k < 6; k++) { Op o; o.kind = Op::R; o.addr = 0xF0001000 + 4 * k; o.dst = &creq[k]; mine.push_back(o); }
			Op c; c.kind = Op::CALL; c.fn = serve; mine.push_back(c);
			// after the operation in progress
			if (!ops.empty() && op_phase != 0) {
				Op cur = ops.front(); ops.pop_front();
				for (auto it = mine.rbegin(); it != mine.rend(); ++it) ops.push_front(*it);
				ops.push_front(cur);
			} else for (auto it = mine.rbegin(); it != mine.rend(); ++it) ops.push_front(*it);
		}
		core_req_d = creq_now && serving;
		host_step();

		if (pc_every > 0 && t >= next_pc) {
			next_pc += pc_every;
			printf("[%9.3f ms] pc %08x reset %d halted %d fb %08x geom %08x reads %ld writes %ld\n", t, top->dbg_pc,
			       top->dbg_falcon_reset, top->dbg_halted, top->dbg_fb, top->dbg_geom, n_reads, n_writes);
			fflush(stdout);
		}
	}

	svSetScope(svGetScopeFromName("TOP.tb_top"));
	for (uint32_t a : texts) {
		printf("text at %06x: \"", a);
		for (int k = 0; k < 200; k++) { int c = guest_peek8(a + k); if (!c) break; putchar(c >= 32 && c < 127 ? c : '.'); }
		printf("\"\n");
	}
	for (uint32_t a : peeks)
		printf("long at %06x: %08x\n", a, guest_peek8(a) << 24 | guest_peek8(a + 1) << 16 | guest_peek8(a + 2) << 8 | guest_peek8(a + 3));
	if (write_back) for (int id = 1; id <= 6; id++) if (files[id].dirty) {
		FILE *f = fopen(files[id].path.c_str(), "r+b");
		if (f) { fwrite(files[id].data.data(), 1, files[id].data.size(), f); fclose(f); }
	}
	int errs = top->sd_model_errors + top->sram_errors;
	if (check_screen) {
		// the last screen against Videl's last two frames, scaled as gb_fb's
		// header says (RGB 5:6:5 kept), interlace not handled here
		long bad = 0, n = 0;
		for (int k = 0; k < 2 && (k == 0 || bad); k++) {
			auto &fr = k ? prev_frame : last_frame;
			int fw = k ? prev_w : last_w, fh = k ? prev_h : last_h;
			if (!fw) continue;
			auto fitf = [](int v, int t2, int t3, int t4) { return v <= t4 ? 4 : v <= t3 ? 3 : v <= t2 ? 2 : 1; };
			int sx = fitf(fw, 400, 266, 200), sy = fitf(fh, 240, 160, 120);
			if (sx > 2 * sy) sx = 2 * sy; else if (sy > 2 * sx) sy = 2 * sx;
			bad = 0; n = 0;
			for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++) {
				int px, py;
				if (!hdmi) {
					int ex = fw * sx, ey = fh * sy, ox = (720 - ex) >> 1, oy = (480 - ey) >> 1;
					if (720 - ex < 0) ox = -((ex - 720 + 1) / 2);
					px = (x >= ox && x < ox + ex) ? (x - ox) / sx : -1; py = (y >= oy && y < oy + ey) ? (y - oy) / sy : -1;
				} else {
					int ex = (fw * 3 * sx + 1) / 2, ey = (fh * 3 * sy + 1) / 2, ox = (1280 - ex) / 2, oy = (720 - ey) / 2;
					px = (x >= ox && x < ox + ex) ? 2 * (x - ox) / (3 * sx) : -1; py = (y >= oy && y < oy + ey) ? 2 * (y - oy) / (3 * sy) : -1;
				}
				uint32_t want = 0;
				if (px >= 0 && py >= 0) {
					uint32_t c = fr[py * fw + px];
					uint32_t r = (c >> 16) & 0xF8, g = (c >> 8) & 0xFC, b = c & 0xF8;
					want = (r | r >> 5) << 16 | (g | g >> 6) << 8 | (b | b >> 5);
				}
				n++;
				if (screen[y * SW + x] != want) bad++;
			}
			printf("screen check against Videl's %s frame (%dx%d, x%d y%d): %ld of %ld pixels differ\n",
			       k ? "previous" : "last", fw, fh, sx, sy, bad, n);
		}
		if (bad) errs++;
	}
	printf("end %.1f ms: pc %08x, %d Videl frames, %d screens (last %08x), %ld blocks read, %ld written, "
	       "SDRAM errors %u, SRAM errors %u, fb %08x, geometry %08x\n",
	       now_ms(), top->dbg_pc, vframe, scr_n, last_screen_sum, n_reads, n_writes,
	       top->sd_model_errors, top->sram_errors, top->dbg_fb, top->dbg_geom);
	if (expect_screen >= 0 && (uint32_t)expect_screen != last_screen_sum) { printf("FAIL: screen %08x, expected %08lx\n", last_screen_sum, expect_screen); errs++; }
	printf(errs ? "FAIL\n" : "PASS\n");
	top->final();
	delete top;
	return errs ? 1 : 0;
}
