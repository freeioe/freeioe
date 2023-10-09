# !/usr/bin/env sh

set -e

if [ $# -lt 3 ] ; then
	echo "Usage: build_skynet.sh <cpu arch> <toolchain script name> <freeioe dir>"
	exit 0
fi

PLAT_ARCH=$1
TOOLCHAIN=$2
SKYNET_DIR=$3
FREEIOE_DIR=$4

cd $SKYNET_DIR


printf "ARCH: $PLAT_ARCH \t TOOLCHAINE: $TOOLCHAIN \t FREEIOE_DIR: $FREEIOE_DIR \n"

echo "Make Clean Up"
make cleanall > /dev/null 2>&1

if [ "$TOOLCHAIN" == "native" ]; then
	unset CC
	unset CXX
	unset AR
	unset STRIP
	make linux -j8 > /dev/null 2>&1
else
	echo "=== export toolchain ==="
	source ~/toolchains/$TOOLCHAIN
	echo $CC
	echo "========================"
	make openwrt -j8 > /dev/null 2>&1
fi

if [ $? -ne 0 ]; then
	echo "*********** ERROR Build SKYNET failed **************"
	exit
fi

strip_files() {
	echo "=========STRIP FILE==============="
	ls -lh $SKYNET_DIR/skynet
	$STRIP $SKYNET_DIR/skynet
	find $SKYNET_DIR/cservice/ -mindepth 1 | xargs $STRIP
	find $SKYNET_DIR/luaclib/ -mindepth 1 | grep so | xargs $STRIP
	ls -lh $SKYNET_DIR/skynet
}

if [ -f "$SKYNET_DIR/skynet" ]
then
	file $SKYNET_DIR/skynet

	ARCH_R="${PLAT_ARCH##*/}"
	case $ARCH_R in
	mipsel_24kc | mips_24kc)
		strip_files
		;;
	*)
		echo "===========FILES ARE NOT STRIPED ============="
		;;
	esac

	bash $FREEIOE_DIR/scripts/release_skynet.sh $SKYNET_DIR $PLAT_ARCH $FREEIOE_DIR/__release
else
	echo "*********** ERROR skynet file missing **************"
fi


echo "===============================DONE=================================="

