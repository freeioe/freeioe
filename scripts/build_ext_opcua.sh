#!/usr/bin/env bash
#
# Build OPC-UA Extension
# Builds the open62541 OPC-UA library for specified platform
#
# Usage: build_ext_opcua.sh <cpu_arch> <toolchain> <source_dir>
#
# Arguments:
#   cpu_arch   - CPU architecture (e.g., openwrt/19.07/arm_cortex-a7_neon-vfpv4)
#   toolchain  - Toolchain name or "native" for local builds
#   source_dir - Path to open62541 source directory (should contain open62541.spec)
#
# Prerequisites:
#   - Source directory must contain open62541.spec file
#   - For cross-compilation: toolchain files must be in ~/toolchains/
#   - Build scripts (build_lib.sh, build_lib_openwrt.sh) must exist in source dir
#
# Examples:
#   build_ext_opcua.sh native native /path/to/open62541
#   build_ext_opcua.sh openwrt/19.07/arm_cortex-a7_neon-vfpv4 Toolchain-arm-openwrt-linux-gcc.cmake /path/to/open62541
#

set -e

# Validate arguments
if [ $# -lt 3 ] ; then
	echo "Usage: build_ext_opcua.sh <cpu arch> <toolchain script name> <source dir>"
	exit 0
fi

PLAT_ARCH=$1
TOOLCHAIN=$2
SOURCE_DIR=$3

printf "ARCH: $PLAT_ARCH \t TOOLCHAINE: $TOOLCHAIN \t SOURCE: $SOURCE_DIR \n"

# Platform-specific toolchain mappings
declare -A toolchains

# Native builds
toolchains["linux/x86_64"]="native"

# OpenWrt 17.01 toolchains
toolchains["openwrt/17.01/arm_cortex-a9_neon"]="Toolchain-arm-openwrt-linux-gcc.cmake"
toolchains["openwrt/17.01/arm_cortex-a7_neon_gcc"]="Toolchain-arm-openwrt-linux-gcc.cmake"

# OpenWrt 18.06 toolchains
# toolchains["openwrt/14.07/mipsel_24kc"]="Toolchain-mipsel_24kc-openwrt-linux-gcc.cmake"
toolchains["openwrt/18.06/mips_24kc"]="Toolchain-mips_24kc-openwrt-linux-gcc.cmake"
# toolchains["openwrt/18.06/x86_64"]="Toolchain-x86_64-openwrt-linux-gcc.cmake"

# OpenWrt 19.07 toolchains
toolchains["openwrt/19.07/arm_cortex-a9_neon"]="Toolchain-arm-openwrt-linux-gcc.cmake"
toolchains["openwrt/19.07/arm_cortex-a7_neon-vfpv4"]="Toolchain-arm-openwrt-linux-gcc.cmake"
toolchains["openwrt/19.07/x86_64"]="Toolchain-x86_64-openwrt-linux-gcc.cmake"

# OpenWrt snapshot toolchains
toolchains["openwrt/snapshot/arm_cortex-a7_neon-vfpv4"]="Toolchain-arm-openwrt-linux-gcc.cmake"
toolchains["openwrt/snapshot/aarch64_cortex-a53"]="Toolchain-aarch64-openwrt-linux-gcc.cmake"
toolchains["openwrt/snapshot/mipsel_24kc"]="Toolchain-mipsel_24kc-openwrt-linux-gcc.cmake"

# Change to source directory
cd "$SOURCE_DIR"

# Verify we're in the correct directory
if [ ! -f "${SOURCE_DIR}/open62541.spec" ]; then
	echo "ERROR: Incorrect build folder. You need to run build_ext_all in binding/lua"
	exit 1
fi

# Build based on toolchain type
if [ "$TOOLCHAIN" = "native" ]; then
	# Native build
	rm -rf bin build
	mkdir build/
	cd build
	../build_lib.sh > /dev/null
	make > /dev/null
else
	# Cross-compile for OpenWrt
	. ~/toolchains/"$TOOLCHAIN"
	rm -rf bin build_openwrt
	mkdir build_openwrt
	cd build_openwrt
	../build_lib_openwrt.sh "${toolchains[$PLAT_ARCH]}" > /dev/null
	make > /dev/null
fi

echo "----------------------------------DONE---------------------------------"
