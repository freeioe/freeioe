# !/usr/bin/env sh

set -e

if [ $# -lt 3 ] ; then
	echo "Usage: build_ext.sh <cpu arch> <toolchain script name> <target dir>"
	exit 0
fi

PLAT_ARCH=$1
TOOLCHAIN=$2
TARGET_DIR=$3

rm build -rf
rm bin -rf

printf "ARCH: $PLAT_ARCH \t TOOLCHAINE: $TOOLCHAIN \t TARGET: $TARGET_DIR \n"

if [ "$TOOLCHAIN" == "native" ]; then
	premake5 gmake
else
	echo "export toolchain"
	premake5 --file=premake5_openwrt.lua gmake
	. ~/toolchains/$TOOLCHAIN
fi

echo $CC
cd build
make config=release

cd ..
file bin/Release/*.so
cp bin/Release/*.so $TARGET_DIR

echo "===============================DONE=================================="

