#!/usr/bin/env sh
#
# Build Skynet Framework
# Compiles Skynet for specified architecture and toolchain
#
# Usage: build_skynet.sh <cpu_arch> <toolchain> <skynet_dir> <freeioe_dir>
#
# Arguments:
#   cpu_arch    - CPU architecture identifier
#   toolchain   - Toolchain name or "native" for local builds
#   skynet_dir  - Path to Skynet source directory
#   freeioe_dir - Path to FreeIOE project directory
#
# Examples:
#   build_skynet.sh openwrt/19.07/arm_cortex-a7_neon-vfpv4 native ./skynet ./freeioe
#

set -e

# Validate arguments
if [ $# -lt 3 ] ; then
	echo "Usage: build_skynet.sh <cpu arch> <toolchain script name> <freeioe dir>"
	exit 0
fi

PLAT_ARCH=$1
TOOLCHAIN=$2
SKYNET_DIR=$3
FREEIOE_DIR=$4

cd "$SKYNET_DIR"

printf "ARCH: $PLAT_ARCH \t TOOLCHAINE: $TOOLCHAIN \t FREEIOE_DIR: $FREEIOE_DIR \n"

# Clean previous build
echo "Make Clean Up"
make cleanall > /dev/null 2>&1

# Build based on toolchain type
if [ "$TOOLCHAIN" = "native" ]; then
	# Native compilation using gcc-10
#	unset CC
#	unset CXX
	export CC=gcc-10
	export CXX=g++-10
	unset AR
	unset STRIP
	make linux -j8 > /dev/null 2>&1
else
	# Cross-compilation for OpenWrt
	echo "=== Export toolchain environment ==="
	source ~/toolchains/"$TOOLCHAIN"
	echo "$CC"
	echo "========================"
	make openwrt -j8 > /dev/null 2>&1
fi

# Check build result
if [ $? -ne 0 ]; then
	echo "*********** ERROR Build SKYNET failed **************"
	exit 1
fi

# Strip binaries for specific architectures to reduce size
strip_files() {
	echo "=========STRIP FILE==============="
	ls -lh "$SKYNET_DIR/skynet"
	$STRIP "$SKYNET_DIR/skynet"
	find "$SKYNET_DIR/cservice/" -mindepth 1 | xargs $STRIP
	find "$SKYNET_DIR/luaclib/" -mindepth 1 | grep so | xargs $STRIP
	ls -lh "$SKYNET_DIR/skynet"
}

if [ -f "$SKYNET_DIR/skynet" ]; then
	file "$SKYNET_DIR/skynet"

	# Extract architecture from platform string
	ARCH_R="${PLAT_ARCH##*/}"
	case $ARCH_R in
		mipsel_24kc | mips_24kc)
			# Strip binaries for MIPS architectures
			strip_files
			;;
		*)
			echo "===========FILES ARE NOT STRIPED ============="
			;;
	esac

	# Package the release
	bash "$FREEIOE_DIR/scripts/release_skynet.sh" "$SKYNET_DIR" "$PLAT_ARCH" "$FREEIOE_DIR/__release"
else
	echo "*********** ERROR skynet file missing **************"
	exit 1
fi

echo "===============================DONE=================================="
