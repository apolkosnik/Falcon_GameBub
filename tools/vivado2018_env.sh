#!/bin/bash
# Runs tools/build_vivado2018.sh with Vivado 2018.3, a JDK and Python 3.13
# (the paths of the machine this core is built on; adjust for another).
# SPDX-License-Identifier: GPL-2.0-or-later
source ${VIVADO_SETTINGS:-/opt/tools/Xilinx/Vivado/2018.3/settings64.sh}
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-27-openjdk}
export PATH="$(pyenv root)/versions/3.13.5/bin:$JAVA_HOME/bin:$PATH"
exec "$(dirname "$0")/build_vivado2018.sh"
