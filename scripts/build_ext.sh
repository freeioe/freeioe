#!/usr/bin/env sh
#
# Build Extension Library
# Builds native or cross-compiled extension libraries for FreeIOE
#
# Usage: build_ext.sh <cpu_arch> <toolchain> <target_dir>
#
# Arguments:
#   cpu_arch   - CPU architecture (e.g., openwrt/19.07/arm_cortex-a7_neon-vfpv4)
#   toolchain  - Toolchain name or "native" for local builds
#   target_dir - Directory where compiled .so files will be copied
#
# Examples:
#   build_ext.sh openwrt/19.07/arm_cortex-a7_neon-vfpv4 Toolchain-arm-openwrt-linux-gcc.cmake ./output
#   build_ext.sh native native ./output
#

set -e

# Validate arguments
if [ $# -lt 3 ] ; then
	echo "Usage: build_ext.sh <cpu arch> <toolchain script name> <target dir>"
	exit 0
fi

PLAT_ARCH=$1
TOOLCHAIN=$2
TARGET_DIR=$3

# Clean previous build artifacts
rm -rf build bin

printf "ARCH: $PLAT_ARCH \t TOOLCHAINE: $TOOLCHAIN \t TARGET: $TARGET_DIR \n"

# Build based on toolchain type
if [ "$TOOLCHAIN" = "native" ]; then
	# Native build using premake5
	premake5 gmake
else
	# Cross-compile for OpenWrt
	echo "Export toolchain environment"
	premake5 --file=premake5_openwrt.lua gmake
	. ~/toolchains/"$TOOLCHAIN"
fi

# Display compiler being used
echo "$CC"

# Build the extension
cd build
make config=release

# Copy compiled libraries to target directory
cd ..
file bin/Release/*.so
cp bin/Release/*.so "$TARGET_DIR"

echo "===============================DONE=================================="
