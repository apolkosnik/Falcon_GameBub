# Release files

Two cores, each a complete directory to copy to `/cores/` on the microSD card (add a
TOS image, see the top-level README):

* `apolkosnik.Falcon/`: the Falcon030 (AP68030), v0.1.0;
* `apolkosnik.Falcon060/`: the 68060 build variant (`variants/060`, AP68060 and 48 MB of
  CT60 Fast RAM), v0.1.0. It is a core of its own on the card, next to the Falcon030.

Built with Vivado 2018.3 (`tools/build_vivado2018.sh`, `tools/build_variant.sh 060`) and
framework v1.1.0-beta5: they need a firmware that calls itself 1.1.0-beta5 or later
(`min_firmware`). Timing: worst setup slack +0.046 ns (Falcon030) and +0.159 ns (68060).

A USB keyboard or mouse on the dock needs the firmware forks: the handheld's at
`f1b9bec4` (`apolkosnik/gamebub`, branch `minimig-net-beta5`) with
[firmware/0001-dock-keyboard-and-mouse-for-the-Falcon-core.patch](../firmware/README.md),
and the dock's at `8bd58a4` or later (`apolkosnik/dock-firmware`, branch `usb-mouse`).
With the stock firmware the cores run with the handheld's controls and dock controllers.

## v0.1.0

The first release: an Atari Falcon030, and the same Falcon with a 68060, from
Falcon_MiSTer's RTL (see the top-level README). Since the builds of these cores that
have been run on a Game Bub:

* Narrow and short Falcon screens are shown. Pictures up to 200 pixels wide (scaled 4
  times across) or up to 120 lines high (4 times down) were black on the panel and on
  HDMI: the frame store's rule that neither factor is more than twice the other took the
  factor 4 at two bits, 0. Seen as 124 Beers' photo slideshow (200 x 240) missing.
* The SCSI bus no longer stays busy. The empty CD-ROM at SCSI ID 2 answers selection and
  asks for its INQUIRY, READ CAPACITY and MODE SENSE data as disk slot 6, which nothing
  served: the target kept BSY, and EmuTOS waited for a free bus before every SCSI
  selection until it timed out. Slot 6 is now served as an empty image (the target then
  gives its built-in answers), and EmuTOS boots several seconds sooner.
* Jagpads and paddles on the enhanced joystick ports, a USB keyboard and mouse on the
  dock (with the firmware forks).

Tested in simulation on these sources: the frame store's 18 cases (new: 160 x 240,
200 x 240 on the panel and on HDMI, 320 x 120; every pixel checked), the unit, DSP and
input tests, and EmuTOS 1.3 booting from IDE, SCSI and floppy and writing a file to each.
On a Game Bub: earlier builds; these two fixes not yet.

Known: in 124 Beers the first picture and the effect before "THE END" do not look right
on a Game Bub; the core's picture matches Hatari's (with EmuTOS), and the cause is not
known yet. EmuTOS shows the year 2096 (the core has no real-time clock yet).
