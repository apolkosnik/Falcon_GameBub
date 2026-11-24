#!/usr/bin/env python3
"""Import the Falcon RTL from Falcon_MiSTer into rtl/falcon/ and rtl/ap68030/.

    tools/import_falcon.py <Falcon_MiSTer checkout>

The checkout must be at the commit in UPSTREAM_COMMIT (checked). The files are
copied as the framework's build takes them:

  * `include` lines are replaced by the file they name (recursively), so the
    build needs no include paths; include guards are dropped so that every
    file that includes a header gets its macros (Vivado compiles each file
    on its own);
  * the opcode table of falcon_pipescan ($readmemb of falcon_optbl.mem, a
    path relative to the Quartus project) is written into the module as an
    initial block;
  * the edits listed in EDITS are made (each must match exactly once).

SPDX-License-Identifier: GPL-2.0-or-later
"""
import os
import re
import subprocess
import sys

UPSTREAM_URL = "https://github.com/apolkosnik/Falcon_MiSTer"
UPSTREAM_COMMIT = "d9f05d9ac3d6eb77acc021fa902e162d034ac2bd"

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# files from the upstream tree: (source, destination directory)
FALCON = [
    "falcon_system.sv", "falcon_cpubus.sv", "falcon_cpuclk.sv", "falcon_pipescan.sv",
    "falcon_tstat.sv", "falcon_l2.sv", "falcon_memarb.sv", "falcon_combel.sv",
    "falcon_videl.sv", "falcon_psg.sv", "falcon_mfp.sv", "falcon_mfp_timer.sv",
    "falcon_mfp_usart.sv", "falcon_acia.sv", "falcon_ikbd.sv", "falcon_ikbd_keymap.sv",
    "falcon_nvram.sv", "falcon_blitter.sv", "falcon_crossbar.sv", "falcon_ide.sv",
    "falcon_fdc.sv", "falcon_fdc_ncr5380.sv", "falcon_scsi.sv", "falcon_ttdma.sv",
    "falcon_ttshift.sv",
]
DSP = ["falcon_dsp.sv", "dsp56k_core.sv", "dsp56k_dec.sv", "dsp56k_alu.sv",
       "dsp_periph.sv", "dsp_ram.sv", "dsp56k_rom.sv"]
OTHER = ["scc/scc.v", "scc/scc_chan.v", "scu/scu.v", "vme/vme_atw800.sv"]
AP030 = ["ap030_top.v", "ap030_core.v", "ap030_memsys.v", "ap030_mmu.v", "ap030_cache.v",
         "ap030_bus.v", "ap030_alu.v", "ap030_muldiv.v", "ap030_regfile.v"]

# (file, old, new, why)
EDITS = [
    ("falcon_system.sv",
     "module falcon_system #(",
     "// Game Bub: no 68882 (its arithmetic runs on the MiSTer's ARM)\n"
     "`ifndef FALCON_NO_FPU\n`define FALCON_NO_FPU\n`endif\n\n"
     "module falcon_system #(",
     "no FPU bridge"),
    ("falcon_system.sv",
     "\toutput            ce_pix,\n",
     "\toutput            ce_pix,\n"
     "\toutput            vid_de,        // Game Bub: Videl's display enable\n"
     "\toutput            vid_de_tb,     //   one per source line (the second copy of a doubled one)\n"
     "\toutput            vid_field,     //   the interlaced field\n",
     "Videl's enables out to gb_video"),
    ("falcon_system.sv",
     ".ce_pix(ce_pix), .de(videl_de), .de_tb(videl_de_tb), .vbl(videl_vbl), .hbl(videl_hbl)\n);",
     ".ce_pix(ce_pix), .de(videl_de), .de_tb(videl_de_tb), .vbl(videl_vbl), .hbl(videl_hbl),\n"
     "\t.field(vid_field)\n);\nassign vid_de = videl_de, vid_de_tb = videl_de_tb;",
     "Videl's enables out to gb_video"),
    ("falcon_videl.sv",
     "\toutput reg        field,\n",
     "\toutput reg        field,\n"
     "\toutput            lace,            // Game Bub: the frame's VMD bit 1 (interlace)\n",
     "the interlace flag out to gb_fb"),
    ("falcon_videl.sv",
     "reg         fr_ilace;      // frame-latched VMD bit 1\n",
     "reg         fr_ilace;      // frame-latched VMD bit 1\nassign lace = fr_ilace;\n",
     "the interlace flag out to gb_fb"),
    ("falcon_system.sv",
     "\toutput            vid_field,     //   the interlaced field\n",
     "\toutput            vid_field,     //   the interlaced field\n"
     "\toutput            vid_lace,      //   the frame is interlaced\n",
     "Videl's enables out to gb_video"),
    ("falcon_system.sv",
     "\t.field(vid_field)\n);",
     "\t.field(vid_field), .lace(vid_lace)\n);",
     "Videl's enables out to gb_video"),
    ("falcon_system.sv",
     "wire        blit_ack, dsp_ack, mfp_ack, mfp2_ack, acia_ack, tstat_ack, ttdma_ack;\n",
     "wire        blit_ack, dsp_ack, mfp_ack, mfp2_ack, acia_ack, tstat_ack, ttdma_ack;\n"
     "// Game Bub: the DSP's host port answers a clock after the strobe, its data\n"
     "// as it was at the strobe. Its acknowledge depends on the DSP's interrupt\n"
     "// decision of that clock (a host command taken), which with the CPU's bus\n"
     "// multiplexer after it is too long a path for 32 MHz on the Artix-7.\n"
     "reg  [15:0] dsp_dout_q = 16'hFFFF;\n"
     "reg         dsp_ack_q = 1'b0;\n"
     "always @(posedge clk) begin\n"
     "\tdsp_ack_q <= dsp_ack && !dev_reset;\n"
     "\tif (dsp_ack) dsp_dout_q <= dsp_dout;\n"
     "end\n",
     "the DSP host port's answer a clock later (timing)"),
    ("falcon_system.sv",
     "else if (sel_dsp)    begin dev_dout = dsp_dout;    dev_ack = dsp_ack;    end",
     "else if (sel_dsp)    begin dev_dout = dsp_dout_q;  dev_ack = dsp_ack_q;  end",
     "the DSP host port's answer a clock later (timing)"),
    ("falcon_psg.sv",
     "parameter bit    VOL_TABLE  = 1'b1,",
     "parameter bit    VOL_TABLE  = 1'b0,   // Game Bub: linear mixing, no 15 block RAMs",
     "PSG mixing without the 32768 x 15 table"),
]

INC_RE = re.compile(r'^(\s*)`include\s+"([^"]+)"\s*$')


def git_head(path):
    return subprocess.check_output(["git", "-C", path, "rev-parse", "HEAD"], text=True).strip()


def inline(path, search, seen=None):
    seen = seen or []
    out = []
    for line in open(path, encoding="utf-8", errors="replace").read().splitlines():
        m = INC_RE.match(line)
        if not m:
            out.append(line)
            continue
        name = m.group(2)
        for d in [os.path.dirname(path)] + search:
            cand = os.path.join(d, name)
            if os.path.isfile(cand):
                break
        else:
            sys.exit(f"{path}: include {name} not found")
        if cand in seen:
            sys.exit(f"{path}: recursive include {name}")
        body = inline(cand, search, seen + [cand])
        out.append(f"// ---- begin {name} (inlined by tools/import_falcon.py) ----")
        out.extend(strip_guard(body))
        out.append(f"// ---- end {name} ----")
    return out


def strip_guard(lines):
    """Drop a header's `ifndef X / `define X ... `endif guard."""
    idx = [i for i, l in enumerate(lines) if l.strip() and not l.strip().startswith("//")]
    if len(idx) < 3:
        return lines
    a, b, z = idx[0], idx[1], idx[-1]
    m = re.match(r"`ifndef\s+(\w+)", lines[a].strip())
    if m and lines[b].strip() == f"`define {m.group(1)}" and lines[z].strip().startswith("`endif"):
        return lines[:a] + lines[b + 1:z] + lines[z + 1:]
    return lines


def inline_optbl(text, mem):
    rows = [l.strip() for l in open(mem) if l.strip() and not l.startswith("//")]
    assert len(rows) == 65536, len(rows)
    old = "initial $readmemb(OPTBL_MEM, optbl);"
    assert text.count(old) == 1
    init = ["// Hatari's opcode table (falcon_optbl.mem), inlined by tools/import_falcon.py",
            "initial begin"]
    init += [f"\toptbl[{i}] = 9'b{r};" for i, r in enumerate(rows)]
    init.append("end")
    return text.replace(old, "\n".join(init))


def write(dst, lines_or_text):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    text = lines_or_text if isinstance(lines_or_text, str) else "\n".join(lines_or_text) + "\n"
    with open(dst, "w") as f:
        f.write(text)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = os.path.abspath(sys.argv[1])
    head = git_head(src)
    if not head.startswith(UPSTREAM_COMMIT):
        sys.exit(f"{src} is at {head}, expected {UPSTREAM_COMMIT}")
    if subprocess.run(["git", "-C", src, "diff", "--quiet", "HEAD", "--", "rtl"]).returncode:
        sys.exit(f"{src}: rtl/ has local changes")
    R = os.path.join(src, "rtl")
    out_f = os.path.join(ROOT, "rtl", "falcon")
    out_c = os.path.join(ROOT, "rtl", "ap68030")
    for d in (out_f, out_c):
        if os.path.isdir(d):
            for dp, _, fs in os.walk(d):
                for f in fs:
                    if f.endswith((".sv", ".v", ".svh", ".vh")):
                        os.remove(os.path.join(dp, f))

    texts = {}
    for f in FALCON:
        texts[f] = ("\n".join(inline(os.path.join(R, "falcon", f), [])) + "\n", os.path.join(out_f, f))
    for f in DSP:
        texts[f] = ("\n".join(inline(os.path.join(R, "falcon", "dsp", f), [])) + "\n", os.path.join(out_f, "dsp", f))
    for f in OTHER:
        texts[f] = ("\n".join(inline(os.path.join(R, f), [])) + "\n", os.path.join(out_f, os.path.basename(f)))
    for f in AP030:
        texts[f] = ("\n".join(inline(os.path.join(R, "AP68030", "rtl", f), [os.path.join(R, "AP68030", "rtl")])) + "\n",
                    os.path.join(out_c, f))

    t, d = texts["falcon_pipescan.sv"]
    texts["falcon_pipescan.sv"] = (inline_optbl(t, os.path.join(R, "falcon", "falcon_optbl.mem")), d)

    for f, old, new, why in EDITS:
        t, d = texts[f]
        n = t.count(old)
        if n != 1:
            sys.exit(f"edit '{why}' in {f}: {n} matches")
        texts[f] = (t.replace(old, new), d)

    for t, d in texts.values():
        write(d, t)
    write(os.path.join(ROOT, "rtl", "falcon", "UPSTREAM.md"),
          f"# Upstream\n\nImported by `tools/import_falcon.py` from {UPSTREAM_URL} at\n"
          f"commit `{head}`.\n\nEdits:\n\n" +
          "".join(f"* `{f}`: {why}\n" for f, why in dict.fromkeys((f, why) for f, _, _, why in EDITS)) +
          "* every `include` inlined; falcon_pipescan's opcode table inlined\n")
    print(f"imported {len(texts)} files from {head[:8]}")


if __name__ == "__main__":
    main()
