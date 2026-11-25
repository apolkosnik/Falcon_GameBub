#!/bin/bash
# Builds a variant of the core in its own tree, build/variant-<v>/tree:
#   FALCON_MISTER=<Falcon_MiSTer checkout> tools/build_variant.sh 060 [--stage-only]
# 060: the AP68060 (with its FPU) on falcon_cpubus060 in place of the
# AP68030, CT60 mode's Fast RAM (32 MB, the second SDRAM chip), core ID
# apolkosnik.Falcon060 (variants/060). The tree has this repository's
# framework (a link), chisel/, tools/, rtl/gamebub/ and the variant's
# rtl/falcon/ and rtl/ap68060/ (tools/import_falcon.py --variant 060), and
# falcon_gamebub.sv with FALCON_CPU060 defined. Its bitstream is
# build/variant-<v>/tree/build/FalconCore-gamebub_rev4/FalconCore-gamebub_rev4.bit.
# SPDX-License-Identifier: GPL-2.0-or-later
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
V=$1
[ "$V" = 060 ] || { echo "usage: FALCON_MISTER=<dir> $0 060 [--stage-only]" >&2; exit 1; }
[ -d "$FALCON_MISTER/rtl" ] || { echo "FALCON_MISTER=<Falcon_MiSTer checkout> (tools/import_falcon.py's commit)" >&2; exit 1; }
T=$ROOT/build/variant-$V/tree
rm -rf "$T"
mkdir -p "$T/rtl" "$T/metadata"
cp -a "$ROOT/mill" "$ROOT/build.mill" "$ROOT/chisel" "$ROOT/tools" "$ROOT/patches" "$T/"
ln -s "$ROOT/framework" "$T/framework"
cp -a "$ROOT/rtl/gamebub" "$T/rtl/"
cp "$ROOT/variants/$V/falcon060.xdc" "$T/rtl/gamebub/"
{ echo '`define FALCON_CPU060   // tools/build_variant.sh 060'; cat "$ROOT/rtl/falcon_gamebub.sv"; } > "$T/rtl/falcon_gamebub.sv"
python3 "$ROOT/tools/import_falcon.py" --variant "$V" --dest "$T" "$FALCON_MISTER" | grep -v "^0 declarations"
cp "$ROOT/variants/$V/metadata/"*.json "$T/metadata/"
echo "staged $T"
[ "$2" = --stage-only ] && exit 0
cd "$T"
exec tools/vivado2018_env.sh
