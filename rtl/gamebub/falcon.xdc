########################################
# Falcon core constraints (Game Bub)
########################################
# SDRAM interface (rtl/gamebub/gb_sdram.sv), as the Game Bub Minimig core
# drives the same chips (rtl/gamebub/minimig.xdc there).
#
# The SDRAM clock is clk_sdram (clk_mem delayed by 1.694 ns, MMCM CLKOUT4)
# inverted, forwarded by an ODDR (ram/sd_clk_oddr), so the SDRAM takes the
# commands half a clk_mem period plus 1.694 ns after the clk_mem edge that
# changes them. Command, chip select, address, DQM and write data come from
# registers in the I/O blocks; the DQ output enable is one register for all
# 16 pins (the framework has a single direction bit) and stays in the fabric.
create_generated_clock -name sdram_clk_out -invert -divide_by 1 \
    -source [get_pins -hier -filter {NAME =~ */ram/sd_clk_oddr/C}] \
    [get_ports sdram_clk]

set sd_out_regs [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */ram/sd_cs_reg* || NAME =~ */ram/sd_ras_reg || NAME =~ */ram/sd_cas_reg || NAME =~ */ram/sd_we_reg || NAME =~ */ram/sd_dqm_reg* || NAME =~ */ram/sd_ba_reg* || NAME =~ */ram/sd_addr_reg* || NAME =~ */ram/sd_data_out_reg*)}]
set sd_in_regs  [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ */ram/sd_in_q_reg*}]
set_property IOB TRUE $sd_out_regs
set_property IOB TRUE $sd_in_regs

# SDRAM timing at CAS latency 3, the slowest common 133 MHz x16 parts:
# input setup 1.5 ns, hold 0.8 ns, access time tAC 5.4 ns, output hold tOH
# 2.5 ns; 0.1-0.4 ns of traces each way and 0.2 ns of skew.
set sdram_out [get_ports {sdram_cs_n[*] sdram_ras_n sdram_cas_n sdram_we_n sdram_ldqm sdram_udqm sdram_bs[*] sdram_a[*] sdram_dq[*]}]
set_output_delay -clock sdram_clk_out -max  1.7 $sdram_out
set_output_delay -clock sdram_clk_out -min -1.0 $sdram_out

# Read data: the word of SDRAM clock edge e is driven from tAC after edge
# e-1 until tOH after edge e; gb_sdram takes it (sd_in_q) at the clk_mem
# edge one and a half periods after edge e-1: a setup multicycle of 2.
set_input_delay -clock sdram_clk_out -max 6.2 [get_ports sdram_dq[*]]
set_input_delay -clock sdram_clk_out -min 2.7 [get_ports sdram_dq[*]]
set_multicycle_path -setup 2 -from [get_clocks sdram_clk_out] \
    -to [get_clocks -of_objects [get_pins -hier -filter {NAME =~ */clocks/mmcm/CLKOUT0}]]

########################################
# The picture (gb_fb): the SRAM
########################################
# Every SRAM pin comes from a register in its I/O block and WE from an ODDR,
# so the pins change together; the read data goes into I/O block registers.
set_property IOB TRUE [get_cells -hier -filter {(NAME =~ */fb/o_addr_reg* || NAME =~ */fb/o_data_reg* || NAME =~ */fb/o_mask_reg* || NAME =~ */fb/o_oe_n_reg* || NAME =~ */fb/i_data_reg*) && IS_SEQUENTIAL}]
# The SRAM is asynchronous. gb_fb takes read data two clk_mem clocks after
# the edge that puts the address out (three with the safe timing, which
# this does not need to describe). Read data: the address's clock-to-pad
# delay (at most 5 ns), the traces (0.5 ns each way) and a 10 ns part's
# access time; it holds for the address's minimum clock-to-pad delay
# (1.5 ns) plus the part's output hold (2.5 ns) after the next address.
set fb_clk_mem [get_clocks -of_objects [get_pins -hier -filter {NAME =~ */clocks/mmcm/CLKOUT0}]]
set_input_delay -clock $fb_clk_mem -max 16.0 [get_ports sram_io[*]]
set_input_delay -clock $fb_clk_mem -min  4.0 [get_ports sram_io[*]]
set_multicycle_path -setup 2 -from [get_ports sram_io[*]]
set_multicycle_path -hold 1 -from [get_ports sram_io[*]]

# gb_fb between its clocks. The geometry (g_*, clk_sys) is copied in clk_av
# after its toggle went through pub_s; a fetch request (q_*, clk_av) is held
# until it is done and taken by clk_mem after its toggle went through r_ts;
# the done toggle comes back through done_s; sram_safe (clk_sys, a setting)
# through two registers. The line buffers are block RAM written in clk_mem
# and read in clk_av.
set_false_path -to [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */fb/pub_s_reg[0]* || NAME =~ */fb/r_ts_reg[0]* || NAME =~ */fb/done_s_reg[0]* || NAME =~ */fb/safe_s_reg[0]* || NAME =~ */fb/safe_m_reg[0]*)}]
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */fb/g_w_reg* || NAME =~ */fb/g_h_reg* || NAME =~ */fb/g_s_reg* || NAME =~ */fb/g_single_reg*)}] \
    -to [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */fb/a_w_reg* || NAME =~ */fb/a_h_reg* || NAME =~ */fb/a_s_reg* || NAME =~ */fb/a_single_reg*)}]
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ */fb/q_a_reg* || NAME =~ */fb/q_step_reg* || NAME =~ */fb/q_cnt_reg* || NAME =~ */fb/q_slot_reg*)}] \
    -to $fb_clk_mem

# gb_fb's count of scan lines shown late (clk_av) is read by gb_host (clk_sys)
# for the debug registers only.
set_false_path -from [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ */fb/dbg_late_reg*}]
