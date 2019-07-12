#!/usr/bin/env bash

# Absolute path to this script, e.g. /home/user/bin/foo.sh
SCRIPT=$(readlink -f "$0")
# Absolute path this script is in, thus /home/user/bin
SCRIPTPATH=$(dirname "$SCRIPT")
echo $SCRIPTPATH

BUILD_LIB=$1
CUR_DIR=`pwd`

declare -A plats

plats["linux/x86_64"]="native"
#plats["openwrt/arm_cortex-a9_neon"]="imx6_exports.sh"
plats["openwrt/17.01/arm_cortex-a9_neon"]="tg3030_exports.sh"
plats["openwrt/18.06/mips_24kc"]="mips_24kc.sh"
plats["openwrt/18.06/x86_64"]="x86_64_glibc.sh"
#plats["openwrt/aarch64_cortex-a53"]="bp3plus_exports.sh"
plats["openwrt/19.07/arm_cortex-a7_neon-vfpv4"]="sunxi_a7.sh"
# plats["android/arm"]="android_arm.sh"

for item in "${!plats[@]}"; 
do
	if [ "$BUILD_LIB" == "opcua" ]; then
		bash $SCRIPTPATH/build_ext_opcua.sh $item ${plats[$item]} $CUR_DIR/../..
	fi
	mkdir -p $SCRIPTPATH/../feeds/prebuild_exts/$item/
	bash $SCRIPTPATH/build_ext.sh $item ${plats[$item]} $SCRIPTPATH/../feeds/prebuild_exts/$item/
done
