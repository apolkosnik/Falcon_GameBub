import chisel3._
import net.gamebub.framework.Core
import net.gamebub.framework.interface._

/**
 * Atari Falcon030 for the Game Bub.
 *
 * The core itself is SystemVerilog (rtl/); this class only declares the
 * framework interfaces and binds them to the `falcon_gamebub` module.
 *
 * Clocks: one MMCM, 50 MHz * 38.375 / 2 = 959.375 MHz VCO
 *   /10 = 95.94 MHz   SDRAM controller, SRAM frame store (3 x system)
 *   /30 = 31.98 MHz   the Falcon, system clock (32 MHz -0.07 %)
 *   /5  = 191.9 MHz   host SPI
 *   /N  = display clock (N chosen from the display's range)
 */
class FalconCore extends Module with Core {
  val mmcmVcoHz: Double = 50_000_000.0 * 38.375 / 2.0

  // The shortest frame the panel's driver is built for: the Falcon's VGA
  // modes (60 Hz). PAL RGB (50 Hz) makes it wait in its vertical blanking;
  // the mono monitor's 71 Hz frames come faster than it shows them, and
  // some are not shown.
  val framePeriod = 0.0167
  val (displayClockMin, displayClockMax) = ClocksV0.getClockDisplayHz(framePeriod)
  val displayDivider = math.floor(mmcmVcoHz / displayClockMin).toInt
  val displayClock = (mmcmVcoHz / displayDivider).toInt
  require(displayDivider >= 1 && displayDivider <= 128, s"display divider $displayDivider out of range")
  require(displayClock <= displayClockMax, s"display clock $displayClock above $displayClockMax")

  val io = IO(new Bundle {
    val clocks = new ClocksV0(
      clockSystemHz = (mmcmVcoHz / 30).toInt,
      clockDisplayHz = displayClock,
      clockSpiHz = (mmcmVcoHz / 5).toInt,
    )
    val video = new VideoV0(
      // The picture's window: 720 x 480 on the panel (rev 4 shows a 720
      // column picture whole), one to one. The core keeps its frames itself
      // (gb_fb: the Falcon's own resolution in the SRAM and block RAM) and
      // scales them to the panel and to HDMI's 1280 x 720 through the
      // external picture (patches/framework: ownFrames); the framework
      // takes only the stream's timing.
      videoWidth = 720,
      videoHeight = 480,
      colorDepthR = 1,
      colorDepthG = 1,
      colorDepthB = 1,
      framePeriod = framePeriod,
      independentScale = true,
      externalPicture = true,
      ownFrames = true,
    )
    val audio = new AudioV0()
    val host = new HostV0()
    val input = new InputExtendedV0(numSlots = 2)
    val sdram = new SdramV0(addressWidth = 13, dataWidth = 16, bankWidth = 2, chips = 2)
    val sram = new SramV0(addressWidth = 18, dataWidth = 16)
  })

  bindExtModule("falcon_gamebub", io, Map(
    "DISPLAY_DIVIDER" -> displayDivider,
  ))
}
