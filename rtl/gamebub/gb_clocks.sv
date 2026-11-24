// Game Bub Falcon: clock generation.
//
// 50 MHz * 38.375 / 2 = 959.375 MHz VCO (PFD 25 MHz)
//   CLKOUT0  /10  95.9375 MHz  clk_mem: SDRAM controller and the SRAM frame
//                 store (3 x clk_sys, edges aligned)
//   CLKOUT1  /30  31.979 MHz   clk_sys: the Falcon (32 MHz -0.07 %; an exact
//                 32 MHz cannot share a VCO with a 3 x clock and the SPI's
//                 >= 160 MHz from a 50 MHz input)
//   CLKOUT2  /5   191.875 MHz  host SPI
//   CLKOUT3  /N   display clock (N from FalconCore.scala)
//   CLKOUT4  /10  95.9375 MHz  SDRAM clock: clk_mem delayed by 58.5 deg
//                 (1.694 ns, 13 steps of 4.5 deg), drives only the ODDR that
//                 forwards it (inverted) to the SDRAM pin, as the Game Bub
//                 Minimig core does (0.963 ns there, at 113.5 MHz). With
//                 0.912 ns the read data's hold check failed by 0.56 ns
//                 (falcon.xdc); this leaves about 1.8 ns of setup on the read
//                 data and 1.4 ns on the commands
//
// SPDX-License-Identifier: GPL-2.0-or-later

module gb_clocks
#(
	parameter integer DISPLAY_DIVIDER = 35
)
(
	input  wire clk_in_50mhz,
	output wire clk_mem,
	output wire clk_sys,
	output wire clk_sdram,
	output wire clk_display,
	output wire clk_spi,
	output wire locked
);

wire clk_fb, clk_fb_buf;
wire clk_mem_u, clk_sys_u, clk_sdram_u;

MMCME2_BASE #(
	.BANDWIDTH          ("OPTIMIZED"),
	.CLKIN1_PERIOD      (20.000),
	.DIVCLK_DIVIDE      (2),
	.CLKFBOUT_MULT_F    (38.375),
	.CLKFBOUT_PHASE     (0.0),

	.CLKOUT0_DIVIDE_F   (10.000),
	.CLKOUT1_DIVIDE     (30),
	.CLKOUT2_DIVIDE     (5),
	.CLKOUT3_DIVIDE     (DISPLAY_DIVIDER),
	.CLKOUT4_DIVIDE     (10),

	.CLKOUT0_PHASE      (0.0),
	.CLKOUT1_PHASE      (0.0),
	.CLKOUT2_PHASE      (0.0),
	.CLKOUT3_PHASE      (0.0),
	.CLKOUT4_PHASE      (58.5),

	.CLKOUT0_DUTY_CYCLE (0.5),
	.CLKOUT1_DUTY_CYCLE (0.5),
	.CLKOUT2_DUTY_CYCLE (0.5),
	.CLKOUT3_DUTY_CYCLE (0.5),
	.CLKOUT4_DUTY_CYCLE (0.5),

	.STARTUP_WAIT       ("FALSE")
) mmcm (
	.CLKOUT0   (clk_mem_u),
	.CLKOUT0B  (),
	.CLKOUT1   (clk_sys_u),
	.CLKOUT1B  (),
	.CLKOUT2   (clk_spi),
	.CLKOUT2B  (),
	.CLKOUT3   (clk_display),
	.CLKOUT3B  (),
	.CLKOUT4   (clk_sdram_u),
	.CLKOUT5   (),
	.CLKOUT6   (),
	.CLKFBOUT  (clk_fb),
	.CLKFBOUTB (),
	.CLKFBIN   (clk_fb_buf),
	.LOCKED    (locked),
	.CLKIN1    (clk_in_50mhz),
	.PWRDWN    (1'b0),
	.RST       (1'b0)
);

BUFG bufg_fb    (.I(clk_fb),      .O(clk_fb_buf));
BUFG bufg_mem   (.I(clk_mem_u),   .O(clk_mem));
BUFG bufg_sys   (.I(clk_sys_u),   .O(clk_sys));
BUFG bufg_sdram (.I(clk_sdram_u), .O(clk_sdram));

endmodule
