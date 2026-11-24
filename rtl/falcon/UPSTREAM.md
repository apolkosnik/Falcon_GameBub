# Upstream

Imported by `tools/import_falcon.py` from https://github.com/apolkosnik/Falcon_MiSTer at
commit `d9f05d9ac3d6eb77acc021fa902e162d034ac2bd`.

Edits:

* `falcon_system.sv`: no FPU bridge
* `falcon_system.sv`: Videl's enables out to gb_video
* `falcon_videl.sv`: the interlace flag out to gb_fb
* `falcon_system.sv`: the DSP host port's answer a clock later (timing)
* `falcon_psg.sv`: PSG mixing without the 32768 x 15 table
* every `include` inlined; falcon_pipescan's opcode table inlined
