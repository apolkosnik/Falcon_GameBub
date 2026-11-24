#!/bin/sh
# Builds the disk images of the tests in sim/media: a 720 KB floppy (.ST)
# and a 32 MB hard disk image (MBR, one FAT16 partition from sector 2048),
# each with \AUTO\WRTEST.PRG (sim/asm/wrtest.s). Needs vasmm68k_mot,
# mtools and mkfs.fat.
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
cd "$(dirname "$0")"
VASM=${VASM:-$(command -v vasmm68k_mot || echo /opt/amiga-cc/vbcc/bin/vasmm68k_mot)}
mkdir -p media
"$VASM" -quiet -Ftos -o media/WRTEST.PRG asm/wrtest.s
# floppy
rm -f media/fd.st
mformat -C -f 720 -i media/fd.st ::
mmd -i media/fd.st ::/AUTO
mcopy -i media/fd.st media/WRTEST.PRG ::/AUTO/WRTEST.PRG
# hard disk: the partition, then the MBR in front of it
rm -f media/part.img media/hd.img
dd if=/dev/zero of=media/part.img bs=512 count=63488 status=none
mkfs.fat -F 16 -S 512 -s 4 -n FALCONHD media/part.img > /dev/null
mmd -i media/part.img ::/AUTO
mcopy -i media/part.img media/WRTEST.PRG ::/AUTO/WRTEST.PRG
python3 - <<'PY'
import struct
mbr = bytearray(512)
# one partition: active, FAT16 < 32 MB (type 4), LBA 2048, 63488 sectors
mbr[446:462] = struct.pack('<B3sB3sII', 0x80, b'\xfe\xff\xff', 0x04, b'\xfe\xff\xff', 2048, 63488)
mbr[510:512] = b'\x55\xaa'
with open('media/hd.img', 'wb') as f:
    f.write(mbr)
    f.write(bytes(512 * 2047))
    f.write(open('media/part.img', 'rb').read())
PY
rm media/part.img
ls -la media
