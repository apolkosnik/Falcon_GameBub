########################################
# The 68060 variant (tools/build_variant.sh 060): the processor runs on
# clk_cpu (MMCM CLKOUT5, 47.97 MHz), and falcon_cpubus060 crosses between
# it and clk_sys with toggles, synchronisers and ap030_async_fifo, holding
# the crossing fields steady: the clocks are asynchronous, as Falcon.sdc of
# Falcon_MiSTer declares them.
########################################
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_pins -hier -filter {NAME =~ */clocks/mmcm/CLKOUT5}]]
