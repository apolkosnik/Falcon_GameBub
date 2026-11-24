# Dock keyboard and mouse

The stock Game Bub firmware passes only gamepads to a core. The fork of the
[handheld firmware](https://github.com/apolkosnik/gamebub/tree/minimig-net-beta5)
(branch `minimig-net-beta5`, commit `f1b9bec4`) writes a USB keyboard's keys and a
USB or Bluetooth mouse on the dock (with the
[dock firmware fork](https://github.com/apolkosnik/dock-firmware/tree/usb-mouse)) to the
Minimig core's registers, but only for that core's ID.

The Falcon core takes them at the same registers (`rtl/gamebub/gb_host.sv`: 0x1030 mouse
motion, 0x1034 buttons, 0x1038 key events), so the only change the firmware needs is to
send them to `apolkosnik.Falcon` too:
[0001-dock-keyboard-and-mouse-for-the-Falcon-core.patch](0001-dock-keyboard-and-mouse-for-the-Falcon-core.patch)
(`firmware/lightgun/src/{lib,keyboard,mouse}.rs`). It applies to `f1b9bec4`:

```
git -C gamebub checkout f1b9bec4
git -C gamebub apply ../Falcon_GameBub/firmware/0001-dock-keyboard-and-mouse-for-the-Falcon-core.patch
```

Without it the core works with the handheld's buttons alone (the D-pad / sticks as the
joystick and the mouse, and four buttons as keys; see the README). The patched firmware has
not been built or run here.
