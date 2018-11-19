#!/usr/bin/env bash

if [ $# -lt 3 ] ; then
	echo "Usage: build_ext_opcua.sh <cpu arch> <toolchain script name> <source dir>"
	exit 0
fi

PLAT_ARCH=$1
TOOLCHAIN=$2
SOURCE_DIR=$3

printf "ARCH: $PLAT_ARCH \t TOOLCHAINE: $TOOLCHAIN \t SOURCE: $SOURCE_DIR \n"

declare -A toolchains

toolchains["linux/x86_64"]="native"
toolchains["openwrt/arm_cortex-a9_neon"]="Toolchain-arm-openwrt-linux-gcc.cmake"
toolchains["openwrt/mips_24kc"]="Toolchain-mips_24kc-openwrt-linux-gcc.cmake"
toolchains["openwrt/x86_64"]="Toolchain-x86_64-openwrt-linux-gcc.cmake"
toolchains["openwrt/aarch64_cortex-a53"]="Toolchain-aarch64-openwrt-linux-gcc.cmake"

cd $SOURCE_DIR

if [ "$TOOLCHAIN" == "native" ]; then
	cd ../../
	rm build -rf
	mkdir build/
	cd build
	../build_lib.sh
	make
else
	. ~/toolchains/$TOOLCHAIN
	rm build_openwrt -rf
	mkdir build_openwrt
	cd build_openwrt
	../build_lib_openwrt.sh ${toolchains[$PLAT_ARCH]}
	make
fi

echo "----------------------------------DONE---------------------------------"
