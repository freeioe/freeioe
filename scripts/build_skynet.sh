# !/usr/bin/env sh

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
make cleanall

if [ "$TOOLCHAIN" == "native" ]; then
	unset CC
	unset CXX
	unset AR
	unset STRIP
	make linux
else
	echo "=== export toolchain ==="
	source ~/toolchains/$TOOLCHAIN
	echo $CC
	echo "========================"
	make openwrt
fi

file $SKYNET_DIR/skynet
bash $FREEIOE_DIR/scripts/release_skynet.sh $SKYNET_DIR $PLAT_ARCH $FREEIOE_DIR

echo "===============================DONE=================================="

